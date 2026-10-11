import '../models/course.dart';
import 'store.dart';
import 'notification_service.dart';
import 'scoped_session.dart';
import 'timetable_api.dart';

enum RefreshStatus { success, noSession, expired, networkError, needsHttpPermission }

class RefreshResult {
  final RefreshStatus status;
  final Schedule? schedule;
  final String message;

  /// 本次同步是否检测到课程变动
  final bool hasChanges;

  /// 变动摘要，如 "新增 2 门，取消 1 门"
  final String changeSummary;

  RefreshResult(this.status, this.schedule, this.message,
      {this.hasChanges = false, this.changeSummary = ''});
}

/// 用保存的统一身份认证会话刷新课表。
///
/// 先换新 JWT；课表网关会话失效时，使用保存的学校 CAS 会话重新取得
/// 网关 Cookie。CAS 自身无效时仍需要重新登录，不声称永久登录。
class SyncService {
  static Future<RefreshResult>? _inFlight;

  /// 用保存下来的会话刷新（下拉刷新 / 后台任务 / 手动同步走这条路）。
  ///
  /// 先只取当前教学周和本地缓存比对，一致就说明课表没变（省流量）；
  /// 有出入再整学期重抓一遍。
  static Future<RefreshResult> refreshWithStoredSession() {
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  static Future<RefreshResult> _refresh() async {
    if (!Store.hasSchoolSession) {
      if (Store.token.isNotEmpty) {
        await NotificationService.notifyLoginExpired();
        return RefreshResult(RefreshStatus.expired, Store.schedule, '登录已失效，请重新登录');
      }
      return RefreshResult(
          RefreshStatus.noSession, Store.schedule, '尚未登录，请先完成统一身份认证');
    }
    final cached = Store.schedule;
    try {
      final jar = Store.schoolCookies..addLegacyGateway(Store.cookie);
      final session = SchoolSessionClient(jar, allowAuthHttp: Store.casHttpAllowed);
      try {
        final token = await session.ensureAuthenticated();
        await Store.saveToken(token);
      } finally {
        session.close();
        await Store.saveSchoolCookies(jar);
      }
      final api = TimetableApi(token: Store.token, cookie: Store.cookie);
      final info = await api.weekInfo();
      await Store.applyWeekInfo(info.weekIndex, info.termStartDate);
      try {
        await Store.saveLessonTimes(await api.lessonTimes());
      } on SchoolLoginException {
        rethrow;
      } catch (_) {
        // A config outage retains the last verified campus timetable.
      }

      final studentId = TimetableApi.jwtField(Store.token, 'user_no');
      final changedIdentity = studentId.isNotEmpty && studentId != cached.studentId;
      final changedTerm = (info.schoolYear.isNotEmpty && info.schoolYear != cached.year) ||
          (info.semester.isNotEmpty && info.semester != cached.term);
      if (cached.courses.isEmpty || changedIdentity || changedTerm) {
        final courses = await api.fetchSemester(info: info);
        if (courses.isEmpty) {
          return RefreshResult(
              RefreshStatus.networkError, cached, '没有读到课程');
        }
        final s = _build(courses, info, cached);
        await Store.saveSchedule(s);
        await Store.saveLastSync();
        return RefreshResult(RefreshStatus.success, s, '已同步 ${courses.length} 门课程');
      }

      final fresh =
          await api.weekLessons(info.schoolYear, info.semester, info.weekIndex);
      final nowKeys = _keys(fresh);
      final cachedKeys = _keys(
          cached.courses.where((c) => c.activeInWeek(info.weekIndex)).toList());

      if (_sameSet(nowKeys, cachedKeys)) {
        final s = _build(cached.courses, info, cached);
        await Store.saveSchedule(s);
        await Store.saveLastSync();
        return RefreshResult(RefreshStatus.success, s, '课表无变化');
      }

      final courses = await api.fetchSemester(info: info);
      if (courses.isEmpty) {
        return RefreshResult(
            RefreshStatus.networkError, cached, '没有读到课程');
      }
      final s = _build(courses, info, cached);
      await Store.saveSchedule(s);
      await Store.saveLastSync();
      final diff = _diffCourses(cached.courses, courses);
      return RefreshResult(
          RefreshStatus.success, s, '课表有更新，已同步 ${courses.length} 门课程',
          hasChanges: diff.hasChanges, changeSummary: diff.summary);
    } on SchoolLoginException catch (e) {
      if (e.failure == LoginFailure.needsHttpPermission) {
        return RefreshResult(RefreshStatus.needsHttpPermission, cached, e.toString());
      }
      await NotificationService.notifyLoginExpired();
      return RefreshResult(
          RefreshStatus.expired,
          cached, e.toString());
    } catch (e) {
      return RefreshResult(RefreshStatus.networkError, cached,
          e is SchoolTransportException ? e.toString() : '暂时无法同步，请检查网络后重试');
    }
  }

  static Set<String> _keys(List<Course> cs) =>
      {for (final c in cs) '${c.name}|${c.weekday}|${c.periods.join(",")}|${c.place}'};

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  /// 新旧课表 diff：按课程唯一键比对，算出新增/取消的课程
  static _CourseDiff _diffCourses(List<Course> oldList, List<Course> newList) {
    final oldKeys = {for (final c in oldList) c.key};
    final newKeys = {for (final c in newList) c.key};
    final added =
        newList.where((c) => !oldKeys.contains(c.key)).toList();
    final removed =
        oldList.where((c) => !newKeys.contains(c.key)).toList();
    final parts = <String>[];
    if (added.isNotEmpty) {
      final names = added.map((c) => '《${c.name}》').take(3).join('、');
      parts.add('新增${added.length}门$names');
    }
    if (removed.isNotEmpty) {
      final names = removed.map((c) => '《${c.name}》').take(3).join('、');
      parts.add('取消${removed.length}门$names');
    }
    return _CourseDiff(
      added.isNotEmpty || removed.isNotEmpty,
      parts.join('，'),
    );
  }

  static Schedule _build(
          List<Course> courses, WeekInfo info, Schedule cached) =>
      Schedule(
        courses: courses,
        studentId: TimetableApi.jwtField(Store.token, 'user_no').isNotEmpty
            ? TimetableApi.jwtField(Store.token, 'user_no')
            : (cached.studentId.isNotEmpty ? cached.studentId : Store.studentId),
        studentName: TimetableApi.jwtField(Store.token, 'user_name').isNotEmpty
            ? TimetableApi.jwtField(Store.token, 'user_name') : cached.studentName,
        year: info.schoolYear.isEmpty ? cached.year : info.schoolYear,
        term: info.semester.isEmpty ? cached.term : info.semester,
        fetchedAt: DateTime.now(),
      );
}

/// 课程变动 diff 结果
class _CourseDiff {
  final bool hasChanges;
  final String summary;
  const _CourseDiff(this.hasChanges, this.summary);
}
