import '../models/course.dart';
import 'store.dart';
import 'timetable_api.dart';

enum RefreshStatus { success, noSession, expired, networkError }

class RefreshResult {
  final RefreshStatus status;
  final Schedule? schedule;
  final String message;
  RefreshResult(this.status, this.schedule, this.message);
}

/// 用保存的统一身份认证会话刷新课表。
///
/// 只有 CAS 会话 Cookie（NGXCAS）+ 可续期的 JWT，没有账号密码，
/// 所以会话过期后必须用户重新登录，这里只负责检测并上报。
class SyncService {
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
      return RefreshResult(
          RefreshStatus.success, s, '课表有更新，已同步 ${courses.length} 门课程');
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
