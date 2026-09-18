import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'store.dart';
import 'sync_service.dart';
import 'zf_client.dart';

/// 后台任务入口（必须是顶层函数）
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Store.init();
      if (!Store.autoUpdate || !Store.hasCredentials) return true;

      final last = Store.lastSync;
      final interval = Duration(minutes: Store.updateInterval);
      final due = last == null || DateTime.now().difference(last) >= interval;

      if (due) {
        // 到点了：真正刷新一次课表，并重排提醒
        final result = await SyncService.refreshWithStoredSession();
        final s = result.schedule;
        if (s != null) {
          await NotificationService.init();
          await NotificationService.reschedule(s);
        }
        if (result.status == RefreshStatus.expired) {
          await NotificationService.notify('登录已过期', '请打开「fafu课程表」重新登录以继续自动更新');
        }
      } else {
        // 没到点：只做一次轻量请求，让服务器会话保持活跃
        await _keepAlive();
      }
    } catch (_) {
      // 后台任务不允许抛出异常
    }
    return true;
  });
}

/// 轻量保活：正方会话闲置过久会失效，定期访问一次即可续期
Future<void> _keepAlive() async {
  if (!Store.hasSession) return;
  final client = ZfClient()
    ..path = Store.sessionPath
    ..studentId = Store.studentId
    ..studentName = Store.schedule?.studentName ?? '';
  try {
    await client.fetchSchedulePage();
    await Store.saveSession(client.path);
  } catch (_) {
  } finally {
    client.close();
  }
}

class BackgroundService {
  static const String taskName = 'fafu_kebiao_auto_refresh';

  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// 注册周期性后台更新（WorkManager 最小周期为 15 分钟）
  static Future<void> enable(int intervalMinutes) async {
    await init();
    await Workmanager().cancelByUniqueName(taskName);
    await Workmanager().registerPeriodicTask(
      taskName,
      taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.linear,
    );
  }

  static Future<void> disable() async {
    await init();
    await Workmanager().cancelByUniqueName(taskName);
  }
}
