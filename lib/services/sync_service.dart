import 'dart:typed_data';

import '../models/course.dart';
import 'schedule_parser.dart';
import 'store.dart';
import 'timetable_api.dart';
import 'zf_client.dart';

enum RefreshStatus { success, noSession, expired, networkError }

class RefreshResult {
  final RefreshStatus status;
  final Schedule? schedule;
  final String message;
  RefreshResult(this.status, this.schedule, this.message);
}

/// 把「登录 / 抓取 / 解析 / 落地」串起来的服务层
class SyncService {
  /// 开启一次新的登录流程（打开登录页）
  static Future<ZfClient> beginLogin() async {
    final client = ZfClient();
    await client.openLoginPage();
    return client;
  }

  /// 取验证码
  static Future<Uint8List> captcha(ZfClient client) => client.fetchCaptcha();

  /// 提交登录；返回 null 表示成功，否则是错误提示
  static Future<String?> submit(
    ZfClient client, {
    required String studentId,
    required String password,
    required String captcha,
  }) async {
    final err = await client.submitLogin(
      username: studentId,
      password: password,
      captcha: captcha,
    );
    if (err == null) {
      await Store.saveCredentials(studentId, password);
      await Store.saveSession(client.path);
    }
    return err;
  }

  /// 抓取并保存课表
  static Future<Schedule> fetchAndSave(ZfClient client) async {
    final html = await client.fetchSchedulePage();
    final (courses, year, term) = ScheduleParser.parse(html);
    final schedule = Schedule(
      studentId: client.studentId.isNotEmpty ? client.studentId : Store.studentId,
      studentName: client.studentName,
      year: year,
      term: term,
      fetchedAt: DateTime.now(),
      courses: courses,
    );
    await Store.saveSchedule(schedule);
    await Store.saveSession(client.path);
    return schedule;
  }

  /// 用保存下来的会话直接刷新（下拉刷新 / 后台任务走这条路）
  ///
  /// 「我的课表」只需要 CAS Cookie（+可续期的 JWT），所以优先走这条路；
  /// 老的正方会话作为兜底保留。
  static Future<RefreshResult> refreshWithStoredSession() async {
    if (Store.hasCookie) return _refreshTimetable();
    return _refreshZf();
  }

  /// 走「我的课表」接口刷新。
  ///
  /// 先只取当前教学周和本地缓存比对，一致就说明课表没变（省流量）；
  /// 有出入再整学期重抓一遍。
  static Future<RefreshResult> _refreshTimetable() async {
    final cached = Store.schedule;
    try {
      final api = TimetableApi(token: Store.token, cookie: Store.cookie);
      final info = await api.weekInfo();
      await Store.applyWeekInfo(info.weekIndex, info.termStartDate);

      if (cached == null || cached.courses.isEmpty) {
        final courses = await api.fetchSemester(info: info);
        if (courses.isEmpty) {
          return RefreshResult(RefreshStatus.networkError, cached, '没有读到课程');
        }
        final s = _build(courses, info, cached);
        await Store.saveSchedule(s);
        return RefreshResult(RefreshStatus.success, s, '更新成功');
      }

      final fresh =
          await api.weekLessons(info.schoolYear, info.semester, info.weekIndex);
      final nowKeys = _keys(fresh);
      final cachedKeys = _keys(
          cached.courses.where((c) => c.activeInWeek(info.weekIndex)).toList());

      if (_sameSet(nowKeys, cachedKeys)) {
        final s = _build(cached.courses, info, cached);
        await Store.saveSchedule(s);
        return RefreshResult(RefreshStatus.success, s, '更新成功');
      }

      final courses = await api.fetchSemester(info: info);
      if (courses.isEmpty) {
        return RefreshResult(RefreshStatus.networkError, cached, '没有读到课程');
      }
      final s = _build(courses, info, cached);
      await Store.saveSchedule(s);
      return RefreshResult(RefreshStatus.success, s, '更新成功');
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

  static Schedule _build(List<Course> courses, WeekInfo info, Schedule? cached) =>
      Schedule(
        studentId: (cached != null && cached.studentId.isNotEmpty)
            ? cached.studentId
            : Store.studentId,
        studentName: cached?.studentName ?? '',
        year: info.schoolYear.isEmpty ? (cached?.year ?? '') : info.schoolYear,
        term: info.semester.isEmpty ? (cached?.term ?? '') : info.semester,
        fetchedAt: DateTime.now(),
        courses: courses,
      );

  /// 老的正方教务系统：用保存的会话路径刷新
  static Future<RefreshResult> _refreshZf() async {
    if (!Store.hasSession) {
      return RefreshResult(RefreshStatus.noSession, Store.schedule, '尚未登录');
    }
    final client = ZfClient()
      ..path = Store.sessionPath
      ..studentId = Store.studentId;

    final cached = Store.schedule;
    client.studentName = cached?.studentName ?? '';

    try {
      final html = await client.fetchSchedulePage();
      final (courses, year, term) = ScheduleParser.parse(html);
      if (courses.isEmpty && (cached?.courses.isNotEmpty ?? false)) {
        // 解析不到内容，可能是会话失效的中间页
        return RefreshResult(RefreshStatus.expired, cached, '会话可能已失效');
      }
      final schedule = Schedule(
        studentId: client.studentId,
        studentName: client.studentName,
        year: year,
        term: term,
        fetchedAt: DateTime.now(),
        courses: courses,
      );
      await Store.saveSchedule(schedule);
      await Store.saveSession(client.path);
      return RefreshResult(RefreshStatus.success, schedule, '更新成功');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('会话已失效')) {
        await Store.clearSession();
        return RefreshResult(RefreshStatus.expired, cached, '登录已过期，请重新登录');
      }
      return RefreshResult(RefreshStatus.networkError, cached, '网络异常：$msg');
    } finally {
      client.close();
    }
  }
}
