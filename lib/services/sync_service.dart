import '../models/course.dart';
import 'store.dart';
import 'timetable_api.dart';

enum RefreshStatus { success, noSession, expired, networkError }

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
/// 只有 CAS 会话 Cookie（NGXCAS）+ 可续期的 JWT，没有账号密码，
/// 所以会话过期后必须用户重新登录，这里只负责检测并上报。
class SyncService {
  /// 心跳保活：每次后台唤醒都调一次，续 CAS 会话 + JWT。
  ///
  /// 用最轻量的 `/he/token`（带 Cookie 换 JWT）：
  ///   * 成功 → 会话存活，顺手把新 JWT 存下来；
  ///   * 返回 HTML/抛"重新登录" → CAS 会话已死；
  ///   * 网络异常 → 这次心跳作废，下次再试。
  /// 返回 true 表示会话存活。
  static Future<bool> heartbeat() async {
    if (!Store.hasCookie) return false;
    try {
      final token =
          await TimetableApi.fetchTokenWithCookie(Store.cookie);
      await Store.saveToken(token);
      await Store.saveLastHeartbeat();
      return true;
    } catch (e) {
      final msg = '$e';
      if (msg.contains('重新登录') || msg.contains('会话已失效')) {
        // 会话已死，记一次心跳时间（证明任务在跑，只是会话没了）
        await Store.saveLastHeartbeat();
        return false;
      }
      // 纯网络问题：不记时间，下次唤醒再试
      return false;
    }
  }

  /// 用保存下来的会话刷新（下拉刷新 / 后台任务 / 手动同步走这条路）。
  ///
  /// 先只取当前教学周和本地缓存比对，一致就说明课表没变（省流量）；
  /// 有出入再整学期重抓一遍。
  static Future<RefreshResult> refreshWithStoredSession() async {
    if (!Store.hasCookie) {
      return RefreshResult(
          RefreshStatus.noSession, Store.schedule, '尚未登录，请先完成统一身份认证');
    }
    final cached = Store.schedule;
    try {
      final api = TimetableApi(token: Store.token, cookie: Store.cookie);
      final info = await api.weekInfo();
      await Store.applyWeekInfo(info.weekIndex, info.termStartDate);

      if (cached.courses.isEmpty) {
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
    } catch (e) {
      final msg = '$e';
      if (msg.contains('重新登录') || msg.contains('凭据已失效')) {
        return RefreshResult(RefreshStatus.expired, cached, '登录已过期，请重新登录');
      }
      return RefreshResult(RefreshStatus.networkError, cached, '网络异常：$msg');
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
        studentId:
            cached.studentId.isNotEmpty ? cached.studentId : Store.studentId,
        studentName: cached.studentName,
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
