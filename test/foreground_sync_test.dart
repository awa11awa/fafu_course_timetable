import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fafu_kebiao/main.dart';
import 'package:fafu_kebiao/services/store.dart';
import 'package:fafu_kebiao/services/sync_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'auto_update': true});
    await Store.init();
  });

  testWidgets('cold launch syncs independently of the background interval',
      (tester) async {
    var calls = 0;
    await Store.saveLastSync();
    await Store.saveUpdateInterval(360);
    await tester.pumpWidget(MaterialApp(home: MainShell(refresh: () async {
      calls++;
      return RefreshResult(RefreshStatus.success, null, 'fixture success');
    })));
    await tester.pump();
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resume syncs after the debounce and short repeated resumes do not',
      (tester) async {
    var calls = 0;
    var now = DateTime.utc(2026, 1, 1);
    await tester.pumpWidget(MaterialApp(home: MainShell(
      clock: () => now,
      refresh: () async {
        calls++;
        return RefreshResult(RefreshStatus.success, null, 'fixture success');
      },
    )));
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1);
    now = now.add(const Duration(seconds: 31));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled auto-sync performs no foreground requests', (tester) async {
    await Store.saveAutoUpdate(false);
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: MainShell(refresh: () async {
      calls++;
      return RefreshResult(RefreshStatus.success, null, 'fixture success');
    })));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
