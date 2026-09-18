import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/notification_service.dart';
import '../services/store.dart';
import '../services/sync_service.dart';
import '../theme.dart';
import '../widgets/course_card.dart';
import '../widgets/week_picker.dart';

class HomePage extends StatefulWidget {
  final VoidCallback onLogout;
  const HomePage({super.key, required this.onLogout});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Schedule? _schedule;
  bool _busy = false;
  String _tip = '';

  @override
  void initState() {
    super.initState();
    _schedule = Store.schedule;
  }

  /// 让用户选「现在是第几周」，App 据此反推开学日期（正方页面没有当前周次信息）
  Future<void> _pickWeek(int current) async {
    final maxWeek = _schedule?.maxWeek ?? 20;
    final ok = await showWeekPicker(context, maxWeek: maxWeek, current: current);
    if (ok && mounted) setState(() {});
  }

  Future<void> _refresh() async {    setState(() => _busy = true);
    final r = await SyncService.refreshWithStoredSession();
    final s = r.schedule ?? Store.schedule;
    if (s != null) await NotificationService.reschedule(s);
    if (!mounted) return;
    setState(() {
      _schedule = s;
      _busy = false;
      _tip = switch (r.status) {
        RefreshStatus.success => '已更新',
        RefreshStatus.expired => '登录已过期，请到「设置」重新登录',
        RefreshStatus.noSession => '尚未登录',
        RefreshStatus.networkError => '网络异常，显示的是缓存数据',
      };
    });
    if (_tip.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_tip)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final week = Store.weekOf(now);
    final today = _schedule?.dayCourses(now.weekday, week) ?? <Course>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('fafu课程表'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            if (!Store.hasTermStart)
              WeekHintBanner(onTap: () => _pickWeek(week)),
            _header(now, week),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('今日课程',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text)),
                const SizedBox(width: 8),
                Text('共 ${today.length} 节',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textFaint)),
                const Spacer(),
                if (Store.lastSync != null)
                  Text('更新于 ${_fmtTime(Store.lastSync!)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
            const SizedBox(height: 12),
            if (today.isEmpty)
              _empty(now)
            else
              ...today.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CourseCard(course: c, highlight: _isNext(c, now)),
                  )),
          ],
        ),
      ),
    );
  }

  bool _isNext(Course c, DateTime now) {
    if (c.startTime.isEmpty) return false;
    final p = c.startTime.split(':');
    final start = DateTime(now.year, now.month, now.day,
        int.parse(p[0]), int.parse(p[1]));
    final diff = start.difference(now).inMinutes;
    return diff >= 0 && diff <= 90;
  }

  Widget _header(DateTime now, int week) {
    final name = _schedule?.studentName ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school_outlined, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                name.isEmpty ? '同学，你好' : '$name 同学',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x33FFFFFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('第 $week 周',
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${now.month} 月 ${now.day} 日 · ${Course.weekdayNames[now.weekday - 1]}',
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            _schedule?.termLabel.isNotEmpty == true
                ? _schedule!.termLabel
                : '未获取到学期信息',
            style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _empty(DateTime now) {
    final isWeekend = now.weekday > 5;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(isWeekend ? Icons.weekend_outlined : Icons.free_breakfast_outlined,
              size: 46, color: AppColors.primaryLight),
          const SizedBox(height: 12),
          Text(isWeekend ? '周末愉快，今天没有课' : '今天没有课，好好休息',
              style: const TextStyle(color: AppColors.textSub, fontSize: 14)),
        ],
      ),
    );
  }

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
