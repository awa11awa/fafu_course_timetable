import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/home_page.dart';
import 'pages/login_page.dart';
import 'pages/settings_page.dart';
import 'pages/week_page.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';
import 'services/startup_log.dart';
import 'services/store.dart';
import 'theme.dart';

/// 启动流程刻意保持"极简 + 不阻塞"：
/// 这里只做同步的绑定初始化，随后立刻 runApp。
/// 所有插件（通知、后台任务）的初始化都推迟到首帧之后，并且各自 try/catch，
/// 确保任何一个环节失败都不会让用户看到白屏。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    StartupLog.record('界面异常：${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    StartupLog.record('未捕获异常：$error');
    return true;
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  runApp(const FafuApp());
}

class FafuApp extends StatefulWidget {
  const FafuApp({super.key});

  @override
  State<FafuApp> createState() => _FafuAppState();
}

class _FafuAppState extends State<FafuApp> {
  late Future<void> _boot;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _boot = _bootstrap();
  }

  Future<void> _bootstrap() async {
    // 这一步是必须的：本地存储拿不到就没法工作
    await Store.init();
    _loggedIn = Store.hasCredentials && Store.schedule != null;

    // 插件初始化放到首帧之后，失败也不影响主界面
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await NotificationService.init();
      } catch (e) {
        StartupLog.record('通知服务初始化失败：$e');
      }
      try {
        await BackgroundService.init();
      } catch (e) {
        StartupLog.record('后台任务初始化失败：$e');
      }
      // 若此前排过提醒，启动后顺延一次
      final s = Store.schedule;
      if (s != null) {
        try {
          await NotificationService.reschedule(s);
        } catch (e) {
          StartupLog.record('提醒重排失败：$e');
        }
      }
    });
  }

  void _onLoginDone() => setState(() => _loggedIn = true);

  void _onLogout() => setState(() => _loggedIn = false);

  void _retry() => setState(() => _boot = _bootstrap());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fafu课程表',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<void>(
        future: _boot,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _SplashPage();
          }
          if (snap.hasError) {
            return _StartupErrorPage(
              error: '${snap.error}',
              onRetry: _retry,
            );
          }
          return _loggedIn
              ? MainShell(onLogout: _onLogout)
              : LoginPage(onDone: _onLoginDone);
        },
      ),
    );
  }
}

/// 启动等待页（蓝底 + 图标 + 转圈），避免出现纯白
class _SplashPage extends StatelessWidget {
  const _SplashPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, color: Colors.white, size: 52),
            SizedBox(height: 16),
            Text('fafu课程表',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// 启动失败页：把真实原因显示出来，而不是白屏
class _StartupErrorPage extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _StartupErrorPage({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('启动失败')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFD4380D), size: 46),
          const SizedBox(height: 14),
          const Text('应用初始化时出错',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('下面是具体原因，可截图反馈：',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: SelectableText(error,
                style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onLogout});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(onLogout: widget.onLogout),
      const WeekPage(),
      SettingsPage(onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textFaint,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.today_outlined),
                activeIcon: Icon(Icons.today),
                label: '今日'),
            BottomNavigationBarItem(
                icon: Icon(Icons.calendar_view_week_outlined),
                activeIcon: Icon(Icons.calendar_view_week),
                label: '课表'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings),
                label: '设置'),
          ],
        ),
      ),
    );
  }
}
