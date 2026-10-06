import 'package:flutter/material.dart';

import '../services/background_service.dart';
import '../services/notification_service.dart';
import '../services/startup_log.dart';
import '../services/store.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import 'web_login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const List<int> _leadOptions = [5, 10, 15, 20, 30];
  static const List<int> _intervalOptions = [60, 360, 720, 1440];
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          _section('学校同步'),
          _card([
            _tile(
              icon: Icons.school_outlined,
              title: '统一身份认证登录',
              subtitle: _syncLabel(),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textFaint, size: 20),
              onTap: _openWebLogin,
            ),
            const Divider(height: 1, indent: 14, endIndent: 14),
            _tile(
              icon: Icons.sync_outlined,
              title: '自动同步课表',
              subtitle: Store.hasCookie
                  ? '课程有变动时自动更新到本机'
                  : '需要先完成统一身份认证登录',
              trailing: Switch(
                value: Store.autoUpdate,
                activeThumbColor: AppColors.primary,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(context);
                  await Store.saveAutoUpdate(v);
                  try {
                    if (v) {
                      await BackgroundService.enable();
                    } else {
                      await BackgroundService.disable();
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text('后台任务设置失败：$e')));
                  }
                  setState(() {});
                },
              ),
            ),
            if (Store.autoUpdate) ...[
              const Divider(height: 1, indent: 14, endIndent: 14),
              _tile(
                icon: Icons.timer_outlined,
                title: '同步频率',
                trailing: _dropdown<int>(
                  value: _intervalOptions.contains(Store.updateInterval)
                      ? Store.updateInterval
                      : 360,
                  items: _intervalOptions,
                  label: Store.intervalLabel,
                  enabled: true,
                  onChanged: (v) async {
                    await Store.saveUpdateInterval(v);
                    setState(() {});
                  },
                ),
              ),
            ],
            const Divider(height: 1, indent: 14, endIndent: 14),
            _tile(
              icon: Icons.cloud_download_outlined,
              title: _syncing ? '正在同步…' : '立即同步',
              subtitle: _lastSyncLabel(),
              trailing: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right,
                      color: AppColors.textFaint, size: 20),
              onTap: _syncing ? null : _syncNow,
            ),
          ]),
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
          _section('学期'),
          _card([
            _tile(
              icon: Icons.event_available_outlined,
              title: '开学第一周的周日',
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
              icon: Icons.delete_sweep_outlined,
              title: '清空课表',
              subtitle:
                  '删除本机保存的全部课程（共 ${Store.schedule.courses.length} 门）',
              onTap: _clearAll,
              danger: true,
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
          const SizedBox(height: 22),
          const Center(
            child: Text('fafu课程表 v2.2.0\n支持学校统一身份认证同步，也可手动录入',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.textFaint, height: 1.6)),
          ),
        ],
      ),
    );
  }

  // ---------------- 组件 ----------------
  Widget _buildRemindMode() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
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
                        color:
                            active ? AppColors.primary : AppColors.primaryFaint,
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
                    style:
                        const TextStyle(fontSize: 13.5, color: AppColors.text)),
              ))
          .toList(),
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }

  // ---------------- 行为 ----------------
  String _syncLabel() {
    final s = Store.schedule;
    if (!s.isSynced || s.courses.isEmpty) return '登录学校统一身份认证，一键同步课表';
    final name = s.studentName.isNotEmpty ? s.studentName : s.studentId;
    final t = s.fetchedAt;
    final when = t == null
        ? ''
        : ' · ${t.month}月${t.day}日${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}同步';
    return '${name.isNotEmpty ? name : '已同步'}${s.termLabel.isNotEmpty ? ' ${s.termLabel}' : ''}$when';
  }

  Future<void> _openWebLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebLoginPage(
          onImported: (s) async {
            await NotificationService.reschedule(s);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已同步 ${s.courses.length} 门课程')),
              );
              setState(() {});
            }
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  String _lastSyncLabel() {
    final t = Store.lastSync;
    final hb = Store.lastHeartbeat;
    final syncStr = t == null
        ? '还没有同步过'
        : '上次同步：${t.month}月${t.day}日 '
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (hb == null) return syncStr;
    final hbStr = '${hb.month}月${hb.day}日 '
        '${hb.hour.toString().padLeft(2, '0')}:${hb.minute.toString().padLeft(2, '0')}';
    // 心跳时间能判断保活任务是否在跑
    return '$syncStr\n保活心跳：$hbStr';
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final r = await SyncService.refreshWithStoredSession();
      if (r.schedule != null) {
        await NotificationService.reschedule(r.schedule!);
        Store.version.value++;
      }
      if (mounted) {
        final msg = r.hasChanges && r.changeSummary.isNotEmpty
            ? '${r.message}：${r.changeSummary}'
            : r.message;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        if (r.status == RefreshStatus.expired ||
            r.status == RefreshStatus.noSession) {
          _openWebLogin();
        }
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('同步失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _reschedule() async {
    final n = await NotificationService.reschedule(Store.schedule);
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
      helpText: '选择开学第一周的周日',
    );
    if (picked == null) return;
    // 教学周从周日开始：统一落到所选那一周的周日
    final sunday = picked.subtract(Duration(days: picked.weekday % 7));
    await Store.saveTermStart(sunday);
    await NotificationService.reschedule(Store.schedule);
    setState(() {});
  }

  Future<void> _clearAll() async {
    final count = Store.schedule.courses.length;
    if (count == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('课表已经是空的')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空课表'),
        content: Text('将删除全部 $count 门课程，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('清空', style: TextStyle(color: Color(0xFFD4380D)))),
        ],
      ),
    );
    if (ok != true) return;
    await Store.clearSchedule();
    await NotificationService.cancelAll();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清空课表')));
      setState(() {});
    }
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
}
