import '../models/course.dart';
import 'cas_client.dart';
import 'credential_store.dart';
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
/// v2.2：账号密码加密存在本机（Android Keystore），会话过期时静默重登，
/// 全程无后台任务——打开 App 才联网，划掉、杀后台都不影响。
class SyncService {
  /// 确保会话有效：Cookie 还能用就直接续 JWT；过期了就用存的账号密码静默重登。
  ///
  /// 返回 true 表示现在有一个可用会话（Cookie 已就绪）。
  /// 返回 false 表示需要用户手动登录（无存档密码，或静默登录失败）。
  /// [silentRelogin] 为 false 时只检查不重登（用于只想知道状态的场景）。
  static Future<bool> ensureSession({bool silentRelogin = true}) async {
    if (!Store.hasCookie) return false;
    // 先试最轻量的 /he/token：能换到 JWT 说明会话还活着
    try {
      final token = await TimetableApi.fetchTokenWithCookie(Store.cookie);
      await Store.saveToken(token);
      return true;
    } catch (_) {
      // 换不到 → 会话已死，尝试静默重登
    }
    if (!silentRelogin) return false;
    final creds = await CredentialStore.read();
    if (creds == null) return false;
    try {
      final cookie = await CasClient().silentLogin(creds.$1, creds.$2);
      await Store.saveCookie(cookie);
      final token = await TimetableApi.fetchTokenWithCookie(cookie);
      await Store.saveToken(token);
      await Store.saveLastSync();
      return true;
    } on CasLoginException {
      // 静默登不上（验证码/密码错/网络）：清掉失效会话，等用户手动登录
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 用保存下来的会话刷新（下拉刷新 / 打开自动同步 / 手动同步走这条路）。
  ///
  /// 调用前先走 [ensureSession] 保证会话有效。
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
