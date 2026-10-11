import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/services/notification_service.dart';
import 'package:fafu_kebiao/services/store.dart';
import 'package:fafu_kebiao/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AndroidFlutterLocalNotificationsPlugin.registerWith);
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const permissionChannel = MethodChannel('cn.fafu/reminder_permissions');
  final calls = <MethodCall>[];
  var enabled = true;
  var exact = true;
  var revokeExact = false;
  final pending = <int, Map<String, dynamic>>{};

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    enabled = true; exact = true; revokeExact = false;
    calls.clear(); pending.clear();
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (call) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize': return true;
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission': return enabled;
        case 'canScheduleExactNotifications': return exact;
        case 'getNotificationAppLaunchDetails': return {'notificationLaunchedApp': false};
        case 'pendingNotificationRequests': return pending.values.toList();
        case 'cancel': pending.remove((call.arguments as Map)['id'] as int); return null;
        case 'zonedSchedule':
          final args = Map<String, dynamic>.from(call.arguments as Map);
          final platform = args['platformSpecifics'] as Map;
          if (revokeExact && platform['scheduleMode'] == 'exactAllowWhileIdle') {
            throw PlatformException(code: 'exact_alarms_not_permitted');
          }
          pending[args['id'] as int] = {
            'id': args['id'], 'title': args['title'], 'body': args['body'], 'payload': args['payload'],
          };
          return null;
        default: return null;
      }
    });
    await NotificationService.init();
    calls.clear();
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('missing exact alarm permission schedules a visible inexact fallback', () async {
    exact = false;
    expect(await NotificationService.testReminder(), isTrue);
    final args = calls.singleWhere((call) => call.method == 'zonedSchedule').arguments as Map;
    expect((args['platformSpecifics'] as Map)['scheduleMode'], 'inexactAllowWhileIdle');
    expect(args['timeZoneName'], 'Asia/Shanghai');
    expect((await NotificationService.permissions()).label(RemindMode.notification), contains('可能延迟'));
  });

  test('a revocation between permission check and scheduling also falls back', () async {
    revokeExact = true;
    expect(await NotificationService.testReminder(), isTrue);
    expect(calls.where((call) => call.method == 'zonedSchedule'), hasLength(2));
    expect(pending.containsKey(998), isTrue);
  });

  test('notification permission denial reports failure without scheduling', () async {
    enabled = false;
    expect(await NotificationService.testReminder(), isFalse);
    expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    await NotificationService.notifyLoginExpired();
    expect(Store.loginExpiryNotified, isFalse);
    expect(calls.where((call) => call.method == 'show'), isEmpty);
  });

  test('login expiry is deduplicated across restart and reset by a successful login', () async {
    await Future.wait([NotificationService.notifyLoginExpired(), NotificationService.notifyLoginExpired()]);
    await Store.init();
    await NotificationService.notifyLoginExpired();
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
    final shown = calls.singleWhere((call) => call.method == 'show').arguments as Map;
    expect(shown['id'], 900);
    await Store.saveLastSync();
    await NotificationService.loginRestored();
    expect(calls.where((call) => call.method == 'cancel' && (call.arguments as Map)['id'] == 900), hasLength(1));
    await NotificationService.notifyLoginExpired();
    expect(calls.where((call) => call.method == 'show'), hasLength(2));
  });

  test('course rescheduling and disabling do not erase login-expiry notifications', () async {
    pending[1000] = {'id': 1000, 'title': 'course', 'body': '', 'payload': ''};
    pending[900] = {'id': 900, 'title': 'login', 'body': '', 'payload': ''};
    await Store.saveRemindMode(RemindMode.off);
    expect(await NotificationService.reschedule(const Schedule.empty()), 0);
    await NotificationService.cancelAll();
    expect(pending.containsKey(900), isTrue);
    expect(calls.where((call) => call.method == 'cancelAll'), isEmpty);
  });

  test('confirmed expired gateway sends notification even with class reminders off', () async {
    await Store.saveRemindMode(RemindMode.off);
    await Store.saveCookie('NGXCAS=fictional-expired-gateway');
    final result = await http.runWithClient(SyncService.refreshWithStoredSession,
      () => MockClient((request) async => http.Response('', 302, headers: {
        'location': 'http://auth.fafu.edu.cn/authserver/login',
      })),
    );
    expect(result.status, RefreshStatus.expired);
    expect(calls.where((call) => call.method == 'show'), hasLength(1));
  });

  test('network errors keep session and never send a login-expiry notification', () async {
    await Store.saveCookie('NGXCAS=fictional-live-gateway');
    final result = await http.runWithClient(SyncService.refreshWithStoredSession,
      () => MockClient((request) async => throw http.ClientException('offline')),
    );
    expect(result.status, RefreshStatus.networkError);
    expect(Store.hasSchoolSession, isTrue);
    expect(Store.loginExpiryNotified, isFalse);
    expect(calls.where((call) => call.method == 'show'), isEmpty);
  });
}
