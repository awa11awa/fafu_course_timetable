import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';
import 'store.dart';
import 'sync_service.dart';

/// 后台任务入口（必须是顶层函数）
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Store.init();
      if (!Store.autoUpdate) return true;
      // 没有统一身份认证会话就没什么可同步的
      if (!Store.hasCookie) return true;

      final last = Store.lastSync;
      final interval = Duration(minutes: Store.updateInterval);
      final due =
          last == null || DateTime.now().difference(last) >= interval;
      if (!due) return true;

      final result = await SyncService.refreshWithStoredSession();
      final s = result.schedule;
      if (s != null) {
        await NotificationService.init();
        await NotificationService.reschedule(s);
      }
      if (result.status == RefreshStatus.expired) {
        await NotificationService.notifyNow(
            '登录已过期', '请打开「fafu课程表」重新完成统一身份认证，以继续自动同步');
      }
    } catch (_) {
      // 后台任务不允许抛出异常
    }
    return true;
  });
}

class BackgroundService {
  static const String taskName = 'fafu_kebiao_auto_refresh';

  static Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// 注册周期性后台同步（WorkManager 最小周期 15 分钟；
  /// 实际是否同步由 Store.updateInterval 决定，到点才真正请求）。
  static Future<void> enable() async {
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
