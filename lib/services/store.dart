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
  static const _kToken = 'tt_token';
  static const _kCookie = 'tt_cookie';

  /// 「我的课表」的 JWT（1 小时有效，可用下面的 Cookie 续期）
  static String get token => _sp.getString(_kToken) ?? '';
  static Future<void> saveToken(String t) => _sp.setString(_kToken, t);
  static Future<void> clearToken() => _sp.remove(_kToken);

  /// 关键：课表网关只认这个 CAS 会话 Cookie（NGXCAS），只带 JWT 会被打回登录页
  static String get cookie => _sp.getString(_kCookie) ?? '';
  static Future<void> saveCookie(String c) => _sp.setString(_kCookie, c);
  static Future<void> clearCookie() => _sp.remove(_kCookie);
  static bool get hasCookie => cookie.isNotEmpty;

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
  /// 注意：学校教学周是 **周日 → 周六**（第 3 周 = 9/13 周日 ~ 9/19 周六），
  /// 所以第 1 周的起点取那一周的**周日**。
  static Future<void> setCurrentWeek(int week, [DateTime? from]) async {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // weekday: 周一=1 … 周六=6、周日=7 → 回退到本周周日
    final sundayThisWeek = today.subtract(Duration(days: now.weekday % 7));
    final start = sundayThisWeek.subtract(Duration(days: (week - 1) * 7));
    await saveTermStart(start);
  }

  /// 用「我的课表」接口给的信息校准周次基准
  ///
  /// [termStartDate] 就是第 1 周的周日（如 2026-08-30），直接用它最准；
  /// 拿不到才退回用当前周次反推。
  static Future<void> applyWeekInfo(int weekIndex, String termStartDate) async {
    final d = DateTime.tryParse(termStartDate.split(' ').first);
    if (d != null) {
      await saveTermStart(d);
    } else {
      await setCurrentWeek(weekIndex);
    }
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
