import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';

/// 提醒方式
enum RemindMode { off, notification, alarm }

extension RemindModeLabel on RemindMode {
  String get label => switch (this) {
        RemindMode.off => '关闭提醒',
        RemindMode.notification => '推送消息',
        RemindMode.alarm => '闹钟提醒',
      };
}

/// 本地存储：账号、课表缓存、各项设置
class Store {
  static const _kXh = 'xh';
  static const _kPw = 'pw';
  static const _kSchedule = 'schedule_cache';
  static const _kLastSync = 'last_sync';
  static const _kTermStart = 'term_start';
  static const _kRemindMode = 'remind_mode';
  static const _kRemindLead = 'remind_lead';
  static const _kAutoUpdate = 'auto_update';
  static const _kInterval = 'update_interval';
  static const _kRemindCourses = 'remind_courses';
  static const _kSessionPath = 'session_path';
  static const _kSessionAt = 'session_at';
  static const _kBaseUrl = 'base_url';

  /// 校内直连
  static const String baseDirect = 'http://jwgl.fafu.edu.cn';

  /// 校外访问：学校公告「校外访问教务管理系统」给出的 WebVPN 地址
  static const String baseWebVpn = 'https://jwgl.webvpn.fafu.edu.cn:880';

  static late SharedPreferences _sp;

  static Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  // ---------------- 接入地址 ----------------
  static String get baseUrl => _sp.getString(_kBaseUrl) ?? baseDirect;
  static Future<void> saveBaseUrl(String v) => _sp.setString(_kBaseUrl, v);
  static bool get usingWebVpn => baseUrl.startsWith(baseWebVpn);

  // ---------------- 账号 ----------------
  static String get studentId => _sp.getString(_kXh) ?? '';
  static String get password => _sp.getString(_kPw) ?? '';
  static bool get hasCredentials => studentId.isNotEmpty && password.isNotEmpty;

  static Future<void> saveCredentials(String id, String pw) async {
    await _sp.setString(_kXh, id);
    await _sp.setString(_kPw, pw);
  }

  static Future<void> clearCredentials() async {
    await _sp.remove(_kXh);
    await _sp.remove(_kPw);
  }

  // ---------------- 课表缓存 ----------------
  static Schedule? get schedule {
    final raw = _sp.getString(_kSchedule);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Schedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSchedule(Schedule s) async {
    await _sp.setString(_kSchedule, jsonEncode(s.toJson()));
    await _sp.setString(_kLastSync, DateTime.now().toIso8601String());
  }

  static DateTime? get lastSync {
    final v = _sp.getString(_kLastSync);
    return v == null ? null : DateTime.tryParse(v);
  }

  // ---------------- 登录会话 ----------------
  // 正方使用「无 Cookie 会话」，会话 ID 就在 URL 里，把它存下来
  // 后台定时任务就能复用同一会话刷新数据，无需再次输入验证码。
  static String get sessionPath => _sp.getString(_kSessionPath) ?? '';
  static DateTime? get sessionAt {
    final v = _sp.getString(_kSessionAt);
    return v == null ? null : DateTime.tryParse(v);
  }

  static bool get hasSession => sessionPath.isNotEmpty;

  static Future<void> saveSession(String path) async {
    await _sp.setString(_kSessionPath, path);
    await _sp.setString(_kSessionAt, DateTime.now().toIso8601String());
  }

  static Future<void> clearSession() async {
    await _sp.remove(_kSessionPath);
    await _sp.remove(_kSessionAt);
  }

  // ---------------- 学期开始（第 1 周周一） ----------------
  static DateTime? get termStart {
    final v = _sp.getString(_kTermStart);
    return v == null ? null : DateTime.tryParse(v);
  }

  static Future<void> saveTermStart(DateTime d) =>
      _sp.setString(_kTermStart, DateTime(d.year, d.month, d.day).toIso8601String());

  /// 直接告诉 App「现在是第几周」，由它反推开学日期。
  ///
  /// 教务系统页面里没有当前周次信息，App 无法自动得知；而"没设置就当作第 1 周"
  /// 会让「今日」显示为空（很多课从第 2 周才开始）。所以让用户选一次当前周次，
  /// 之后按周自动顺延。
  static Future<void> setCurrentWeek(int week, [DateTime? from]) async {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final mondayThisWeek = today.subtract(Duration(days: now.weekday - 1));
    final start = mondayThisWeek.subtract(Duration(days: (week - 1) * 7));
    await saveTermStart(start);
  }

  /// 是否已设置过周次基准
  static bool get hasTermStart => termStart != null;

  /// 今天是第几周（未设置开学日期时返回 1）
  static int weekOf(DateTime date) {
    final start = termStart;
    if (start == null) return 1;
    final s = DateTime(start.year, start.month, start.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(s).inDays;
    if (diff < 0) return 1;
    return diff ~/ 7 + 1;
  }

  // ---------------- 提醒设置 ----------------
  static RemindMode get remindMode {
    final v = _sp.getString(_kRemindMode) ?? 'notification';
    return RemindMode.values.firstWhere((e) => e.name == v,
        orElse: () => RemindMode.notification);
  }

  static Future<void> saveRemindMode(RemindMode m) =>
      _sp.setString(_kRemindMode, m.name);

  static int get remindLead => _sp.getInt(_kRemindLead) ?? 10;
  static Future<void> saveRemindLead(int m) => _sp.setInt(_kRemindLead, m);

  /// 需要提醒的课程 key 集合（空集合表示全部提醒）
  static Set<String> get remindCourses =>
      (_sp.getStringList(_kRemindCourses) ?? const []).toSet();

  static Future<void> saveRemindCourses(Set<String> keys) =>
      _sp.setStringList(_kRemindCourses, keys.toList());

  // ---------------- 自动更新 ----------------
  static bool get autoUpdate => _sp.getBool(_kAutoUpdate) ?? true;
  static Future<void> saveAutoUpdate(bool v) => _sp.setBool(_kAutoUpdate, v);

  /// 自动更新间隔（分钟），默认 6 小时
  static int get updateInterval => _sp.getInt(_kInterval) ?? 360;
  static Future<void> saveUpdateInterval(int minutes) =>
      _sp.setInt(_kInterval, minutes);

  static String intervalLabel(int minutes) {
    if (minutes < 60) return '$minutes 分钟';
    if (minutes % 60 == 0) return '${minutes ~/ 60} 小时';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '$h 小时 $m 分钟';
  }
}
