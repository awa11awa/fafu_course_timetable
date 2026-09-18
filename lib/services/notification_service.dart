import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import 'reminder_planner.dart';
import 'store.dart';

/// 上课提醒：两种方式
///  * 推送消息 —— 普通通知，响一声，安静地出现在通知栏
///  * 闹钟提醒 —— 最高优先级 + 全屏弹出 + 闹钟铃声 + 震动，需手动划掉
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelNormal = 'fafu_class_reminder';
  static const String channelAlarm = 'fafu_class_alarm';

  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    // 本应用面向福建农林大学，统一使用中国标准时间
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin
        ?.createNotificationChannel(const AndroidNotificationChannel(
      channelNormal,
      '上课提醒',
      description: '课程开始前以通知形式提醒',
      importance: Importance.high,
    ));
    await androidPlugin
        ?.createNotificationChannel(const AndroidNotificationChannel(
      channelAlarm,
      '上课闹钟',
      description: '课程开始前以闹钟形式提醒（全屏 + 铃声 + 震动）',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));

    _ready = true;
  }

  /// 申请通知权限与精确闹钟权限
  static Future<bool> requestPermissions() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final n = await android?.requestNotificationsPermission() ?? true;
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
    return n;
  }

  static NotificationDetails _details(RemindMode mode) {
    if (mode == RemindMode.alarm) {
      return const NotificationDetails(
        android: AndroidNotificationDetails(
          channelAlarm,
          '上课闹钟',
          channelDescription: '课程开始前以闹钟形式提醒',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          ticker: '上课闹钟',
          styleInformation: BigTextStyleInformation(''),
        ),
      );
    }
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        channelNormal,
        '上课提醒',
        channelDescription: '课程开始前以通知形式提醒',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(''),
      ),
    );
  }

  /// 依据当前课表与设置，重排未来所有提醒
  static Future<int> reschedule(Schedule schedule) async {
    await init();
    await _plugin.cancelAll();

    final mode = Store.remindMode;
    if (mode == RemindMode.off) return 0;

    // 只排未来 14 天，随每次数据更新滚动顺延
    final items = ReminderPlanner.upcoming(
      schedule,
      days: 14,
      leadMinutes: Store.remindLead,
    );
    var id = 1000;
    var count = 0;
    for (final it in items) {
      final when = tz.TZDateTime.from(it.when, tz.local);
      if (when.isBefore(tz.TZDateTime.now(tz.local))) continue;
      try {
        await _plugin.zonedSchedule(
          id: id++,
          title: mode == RemindMode.alarm
              ? '上课闹钟 · ${it.course.name}'
              : '即将上课 · ${it.course.name}',
          body: it.body,
          scheduledDate: when,
          notificationDetails: _details(mode),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: it.course.key,
        );
        count++;
      } catch (e) {
        debugPrint('schedule failed: $e');
      }
    }
    return count;
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// 后台更新后的提示
  static Future<void> notify(String title, String body) async {
    await init();
    await _plugin.show(
      id: 1,
      title: title,
      body: body,
      notificationDetails: _details(RemindMode.notification),
    );
  }
}
