import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/course.dart';
import 'reminder_planner.dart';
import 'school_clock.dart';
import 'store.dart';

class ReminderPermissions {
  final bool notifications;
  final bool exact;
  final bool fullScreen;
  final int pending;
  const ReminderPermissions(this.notifications, this.exact, this.fullScreen, this.pending);

  String label(RemindMode mode) {
    if (!notifications) return '通知未开启，上课和登录失效提醒无法送达';
    final parts = <String>['通知已开启'];
    if (mode != RemindMode.off) {
      parts.add(exact ? '准时提醒已开启' : '准时提醒未开启，提醒可能延迟');
      if (mode == RemindMode.alarm) {
        parts.add(fullScreen ? '全屏提醒已开启' : '全屏提醒未开启，将使用通知栏提醒');
      }
      parts.add('未来14天已安排 $pending 条上课提醒');
    }
    return parts.join(' · ');
  }
}

class ReminderAlert {
  final int id;
  final String title;
  final String body;
  const ReminderAlert(this.id, this.title, this.body);
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const channelNormal = 'fafu_class_reminder';
  static const channelAlarm = 'fafu_class_alarm';
  static const channelAccount = 'fafu_account_status';
  static const _permissionChannel = MethodChannel('cn.fafu/reminder_permissions');
  static final alarm = ValueNotifier<ReminderAlert?>(null);
  static Future<void>? _initialization;
  static Future<void> _scheduling = Future<void>.value();
  static Future<void>? _expiryNotification;

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static Future<void> init() => _initialization ??= _initialize().catchError((Object error) {
    _initialization = null;
    throw error;
  });

  static Future<void> _initialize() async {
    tz.setLocalLocation(SchoolClock.location);
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_notification')),
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelNormal, '上课提醒', description: '课程开始前以通知形式提醒', importance: Importance.high,
    ));
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelAlarm, '上课闹钟', description: '课程开始前以闹钟形式提醒',
      importance: Importance.max, playSound: true, enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ));
    await _android?.createNotificationChannel(const AndroidNotificationChannel(
      channelAccount, '学校登录与同步', description: '学校登录失效和课表更新提醒', importance: Importance.high,
    ));
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse != null) {
      _onResponse(launch!.notificationResponse!);
    }
  }

  static void _onResponse(NotificationResponse response) {
    try {
      final payload = jsonDecode(response.payload ?? '') as Map<String, dynamic>;
      if (payload['kind'] == 'class_alarm') {
        alarm.value = ReminderAlert(response.id ?? 998, '${payload['title'] ?? '上课闹钟'}', '${payload['body'] ?? ''}');
      }
    } catch (_) {}
  }

  static Future<ReminderPermissions> permissions() async {
    await init();
    final notifications = await _android?.areNotificationsEnabled() ?? true;
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    var fullScreen = false;
    try {
      fullScreen = await _permissionChannel.invokeMethod<bool>('canUseFullScreenIntent') ?? false;
    } catch (_) {}
    final requests = await _plugin.pendingNotificationRequests();
    return ReminderPermissions(notifications, exact, fullScreen,
        requests.where((request) => request.id >= 1000).length);
  }

  static Future<bool> requestPermissions() async {
    await init();
    final granted = await _android?.requestNotificationsPermission() ?? true;
    if (!granted) return false;
    if (Store.remindMode != RemindMode.off && await _android?.canScheduleExactNotifications() == false) {
      await _android?.requestExactAlarmsPermission();
    }
    if (Store.remindMode == RemindMode.alarm) {
      await _android?.requestFullScreenIntentPermission();
    }
    return (await permissions()).notifications;
  }

  static Future<void> openNotificationSettings() async {
    await init();
    await _android?.openAppNotificationSettings();
  }

  static NotificationDetails _details(RemindMode mode) => NotificationDetails(
    android: AndroidNotificationDetails(
      mode == RemindMode.alarm ? channelAlarm : channelNormal,
      mode == RemindMode.alarm ? '上课闹钟' : '上课提醒',
      importance: mode == RemindMode.alarm ? Importance.max : Importance.high,
      priority: mode == RemindMode.alarm ? Priority.max : Priority.high,
      category: mode == RemindMode.alarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
      fullScreenIntent: mode == RemindMode.alarm,
      autoCancel: true, playSound: true, enableVibration: true,
      audioAttributesUsage: mode == RemindMode.alarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
    ),
  );

  static Future<T> _serialized<T>(Future<T> Function() work) {
    final next = _scheduling.then((_) => work());
    _scheduling = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  static Future<void> _cancelCourseReminders() async {
    for (final request in await _plugin.pendingNotificationRequests()) {
      if (request.id >= 1000) await _plugin.cancel(id: request.id);
    }
  }

  static Future<int> reschedule(Schedule schedule) => _serialized(() async {
    await init();
    await _cancelCourseReminders();
    final mode = Store.remindMode;
    if (mode == RemindMode.off) return 0;
    final permission = await permissions();
    if (!permission.notifications) return 0;
    final items = ReminderPlanner.upcoming(schedule, days: 14, leadMinutes: Store.remindLead);
    var count = 0;
    for (final item in items) {
      if (item.when.isBefore(SchoolClock.now())) continue;
      await _schedule(1000 + count, mode == RemindMode.alarm
          ? '上课闹钟 · ${item.course.name}' : '即将上课 · ${item.course.name}',
          item.body, item.when, mode, permission.exact);
      count++;
    }
    return count;
  });

  static Future<void> _schedule(int id, String title, String body, DateTime when,
      RemindMode mode, bool exact) async {
    final payload = mode == RemindMode.alarm
        ? jsonEncode({'kind': 'class_alarm', 'title': title, 'body': body}) : null;
    Future<void> scheduleWith(AndroidScheduleMode schedulingMode) => _plugin.zonedSchedule(
      id: id, title: title, body: body,
      scheduledDate: tz.TZDateTime.from(when, SchoolClock.location),
      notificationDetails: _details(mode), androidScheduleMode: schedulingMode, payload: payload,
    );
    try {
      await scheduleWith(exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle);
    } on PlatformException catch (error) {
      if (!exact || error.code != 'exact_alarms_not_permitted') rethrow;
      await scheduleWith(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static Future<bool> testReminder() => _serialized(() async {
    final permission = await permissions();
    if (!permission.notifications) return false;
    final mode = Store.remindMode == RemindMode.alarm ? RemindMode.alarm : RemindMode.notification;
    await _schedule(998, '上课提醒测试', '提醒功能已正常触发，请返回设置查看提醒权限。',
        SchoolClock.now().add(const Duration(seconds: 10)), mode, permission.exact);
    return true;
  });

  static Future<void> cancelAll() => _serialized(() async {
    await init();
    await _cancelCourseReminders();
    await _plugin.cancel(id: 998);
  });

  static Future<void> dismissAlarm(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  static Future<void> loginRestored() async {
    try {
      await init();
      await _plugin.cancel(id: 900);
    } catch (_) {}
  }

  static Future<void> notifyLoginExpired() => _expiryNotification ??=
      _notifyLoginExpired().whenComplete(() => _expiryNotification = null);

  static Future<void> _notifyLoginExpired() async {
    if (Store.loginExpiryNotified) return;
    try {
      await init();
      if (await _android?.areNotificationsEnabled() == false) return;
      await _plugin.show(
        id: 900, title: '登录已失效，请重新登录',
        body: '学校会话已失效，打开「fafu课程表」重新登录后可继续同步。已保存的课表仍可查看。',
        notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
          channelAccount, '学校登录与同步', importance: Importance.high,
          priority: Priority.high, onlyAlertOnce: true,
        )),
      );
      await Store.markLoginExpiryNotified(true);
    } catch (_) {}
  }

  static Future<void> notifyNow(String title, String body) async {
    await init();
    await _plugin.show(id: 999, title: title, body: body,
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
        channelAccount, '学校登录与同步', importance: Importance.high, priority: Priority.high,
      )),
    );
  }
}
