import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../services/startup_log.dart';
import '../services/store.dart';
import '../services/sync_service.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  final VoidCallback onLogout;
  const SettingsPage({super.key, required this.onLogout});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<int> _leadOptions = [5, 10, 15, 20, 30];
  static const List<int> _intervalOptions = [60, 180, 360, 720, 1440];

  @override
  Widget build(BuildContext context) {
    final s = Store.schedule;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _accountCard(s?.studentName ?? '', Store.studentId),
          const SizedBox(height: 14),
          _section('上课提醒'),
          _card([
            _buildRemindMode(),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _tile(
              icon: Icons.timer_outlined,
              title: '提前提醒',
              trailing: _dropdown<int>(
                value: Store.remindLead,
                items: _leadOptions,
                label: (v) => '$v 分钟',
                enabled: Store.remindMode != RemindMode.off,
                onChanged: (v) async {
                  await Store.saveRemindLead(v);
                  await _reschedule();
                  setState(() {});
                },
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _section('自动更新'),
          _card([
            _tile(
              icon: Icons.autorenew,
              title: '后台自动更新',
              subtitle: '定时从教务系统重新拉取课表',
              trailing: Switch(
                value: Store.autoUpdate,
                onChanged: (v) async {
                  await Store.saveAutoUpdate(v);
                  if (v) {
                    await BackgroundService.enable(Store.updateInterval);
                  } else {
                    await BackgroundService.disable();
                  }
                  setState(() {});
                },
              ),
            ),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _tile(
              icon: Icons.schedule,
              title: '更新间隔',
              subtitle: '系统限制最快 15 分钟一次',
              trailing: _dropdown<int>(
                value: _intervalOptions.contains(Store.updateInterval)
                    ? Store.updateInterval
                    : 360,
                items: _intervalOptions,
                label: Store.intervalLabel,
                enabled: Store.autoUpdate,
                onChanged: (v) async {
                  await Store.saveUpdateInterval(v);
                  if (Store.autoUpdate) {
                    await BackgroundService.enable(v);
                  }
                  setState(() {});
                },
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _section('学期'),
          _card([
            _tile(
              icon: Icons.event_available_outlined,
              title: '开学第一周的周一',
              subtitle: _termStartLabel(),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textFaint, size: 20),
              onTap: _pickTermStart,
            ),
          ]),
          const SizedBox(height: 14),
          _section('数据'),
          _card([
            _tile(
              icon: Icons.sync,
              title: '立即刷新课表',
              subtitle: Store.lastSync == null
                  ? '尚未更新'
                  : '上次更新：${_fmt(Store.lastSync!)}',
              trailing: const Icon(Icons.refresh,
                  color: AppColors.primary, size: 20),
              onTap: _manualRefresh,
            ),
          ]),
          if (StartupLog.hasError) ...[
            const SizedBox(height: 14),
            _section('启动诊断'),
            _card([
              _tile(
                icon: Icons.bug_report_outlined,
                title: '启动过程有问题',
                subtitle: StartupLog.items.last,
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.textFaint, size: 20),
                onTap: _showDiagnostics,
              ),
            ]),
          ],
          const SizedBox(height: 14),
          _section('账号'),
          _card([
            _tile(
              icon: Icons.logout,
              title: '退出登录',
              subtitle: '清除本机保存的账号与课表',
              onTap: _logout,
              danger: true,
            ),
          ]),
          const SizedBox(height: 22),
          const Center(
            child: Text('fafu课程表 v1.0.0\n数据来源于福建农林大学正方教务系统',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: AppColors.textFaint, height: 1.6)),
          ),
        ],
      ),
    );
  }

  // ---------------- 组件 ----------------
  Widget _accountCard(String name, String id) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: Color(0x33FFFFFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? '未登录' : name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(id.isEmpty ? '—' : '学号 $id',
                    style: const TextStyle(
                        color: Color(0xCCFFFFFF), fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindMode() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.notifications_active_outlined,
                  size: 19, color: AppColors.textSub),
              SizedBox(width: 10),
              Text('提醒方式',
                  style: TextStyle(fontSize: 14.5, color: AppColors.text)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: RemindMode.values.map((m) {
              final active = Store.remindMode == m;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () async {
                      await Store.saveRemindMode(m);
                      if (m == RemindMode.off) {
                        await NotificationService.cancelAll();
                      } else {
                        await NotificationService.requestPermissions();
                        await _reschedule();
                      }
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.primaryFaint,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: active ? AppColors.primary : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        switch (m) {
                          RemindMode.off => '关闭',
                          RemindMode.notification => '推送消息',
                          RemindMode.alarm => '闹钟提醒',
                        },
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          color: active ? Colors.white : AppColors.textSub,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 9),
          Text(
            switch (Store.remindMode) {
              RemindMode.off => '已关闭上课提醒',
              RemindMode.notification => '课前以通知栏消息提醒，响一声',
              RemindMode.alarm => '课前以闹钟方式全屏弹出，带铃声与震动',
            },
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: children),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon,
                size: 19,
                color: danger ? const Color(0xFFD4380D) : AppColors.textSub),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14.5,
                          color: danger
                              ? const Color(0xFFD4380D)
                              : AppColors.text)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textFaint)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required bool enabled,
    required void Function(T) onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      isDense: true,
      borderRadius: BorderRadius.circular(10),
      style: const TextStyle(fontSize: 13.5, color: AppColors.primary),
      icon: const Icon(Icons.expand_more, size: 18, color: AppColors.textFaint),
      items: items
          .map((e) => DropdownMenuItem<T>(
                value: e,
                child: Text(label(e),
                    style: const TextStyle(
                        fontSize: 13.5, color: AppColors.text)),
              ))
          .toList(),
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }

  // ---------------- 行为 ----------------
  Future<void> _reschedule() async {
    final s = Store.schedule;
    if (s == null) return;
    final n = await NotificationService.reschedule(s);
    if (mounted && Store.remindMode != RemindMode.off) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已安排 $n 条上课提醒')));
    }
  }

  String _termStartLabel() {
    final d = Store.termStart;
    if (d == null) return '未设置（点击选择，用于计算当前周次）';
    return '${d.year} 年 ${d.month} 月 ${d.day} 日 · 当前第 ${Store.weekOf(DateTime.now())} 周';
  }

  Future<void> _pickTermStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: Store.termStart ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      helpText: '选择开学第一周的周一',
    );
    if (picked == null) return;
    await Store.saveTermStart(picked);
    final s = Store.schedule;
    if (s != null) await NotificationService.reschedule(s);
    setState(() {});
  }

  void _showDiagnostics() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('启动诊断'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              StartupLog.items.join('\n\n'),
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _manualRefresh() async {    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('正在刷新…')));
    final r = await SyncService.refreshWithStoredSession();
    final s = r.schedule ?? Store.schedule;
    if (s != null) await NotificationService.reschedule(s);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.message)));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('将清除本机保存的账号与课表缓存，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定退出')),
        ],
      ),
    );
    if (ok != true) return;
    await BackgroundService.disable();
    await NotificationService.cancelAll();
    await Store.clearSession();
    await Store.clearCredentials();
    widget.onLogout();
  }

  String _fmt(DateTime d) =>
      '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
