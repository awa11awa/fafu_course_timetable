import 'dart:typed_data';

import '../models/course.dart';
import 'schedule_parser.dart';
import 'store.dart';
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

  /// 用保存下来的会话直接刷新（后台任务走这条路）
  static Future<RefreshResult> refreshWithStoredSession() async {
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
