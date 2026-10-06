import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// 本地存储：课表、学期设置、提醒设置、统一身份认证会话
class Store {
  static const _kSchedule = 'schedule_cache';
  static const _kTermStart = 'term_start';
  static const _kRemindMode = 'remind_mode';
  static const _kRemindLead = 'remind_lead';
  static const _kRemindCourses = 'remind_courses';
  static const _kToken = 'tt_token';
  static const _kCookie = 'tt_cookie';
  static const _kXh = 'student_id';
  static const _kLastSync = 'last_sync';

  static late SharedPreferences _sp;

  /// 课表版本号：保存/清空课表后 +1，页面监听它自动刷新
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  // ---------------- 课表 ----------------
  static Schedule get schedule {
    final raw = _sp.getString(_kSchedule);
    if (raw == null || raw.isEmpty) return const Schedule.empty();
    try {
      return Schedule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const Schedule.empty();
    }
  }

  static Future<void> saveSchedule(Schedule s) async {
    await _sp.setString(_kSchedule, jsonEncode(s.toJson()));
    version.value++;
  }

  static Future<void> clearSchedule() async {
    await _sp.remove(_kSchedule);
    version.value++;
  }

  // ---------------- 统一身份认证会话 ----------------
  /// 「我的课表」的 JWT（1 小时有效，可用下面的 Cookie 续期）
  static String get token => _sp.getString(_kToken) ?? '';
  static Future<void> saveToken(String t) => _sp.setString(_kToken, t);
  static Future<void> clearToken() => _sp.remove(_kToken);

  /// 课表网关只认这个 CAS 会话 Cookie（NGXCAS）
  static String get cookie => _sp.getString(_kCookie) ?? '';
  static Future<void> saveCookie(String c) => _sp.setString(_kCookie, c);
  static Future<void> clearCookie() => _sp.remove(_kCookie);
  static bool get hasCookie => cookie.isNotEmpty;

  static String get studentId => _sp.getString(_kXh) ?? '';
  static Future<void> saveStudentId(String id) => _sp.setString(_kXh, id);

  /// 用接口返回的周次信息校准开学日期。
  /// [termStartDate] 就是第 1 周的周日，直接用它最准；拿不到才退回用当前周次反推。
  static Future<void> applyWeekInfo(int weekIndex, String termStartDate) async {
    final d = DateTime.tryParse(termStartDate.split(' ').first);
    if (d != null) {
      await saveTermStart(d);
    } else {
      await setCurrentWeek(weekIndex);
    }
  }

  // ---------------- 同步 ----------------
  static DateTime? get lastSync {
    final v = _sp.getString(_kLastSync);
    return v == null ? null : DateTime.tryParse(v);
  }

  static Future<void> saveLastSync() =>
      _sp.setString(_kLastSync, DateTime.now().toIso8601String());

  // ---------------- 学期开始（第 1 周周日） ----------------
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
}
