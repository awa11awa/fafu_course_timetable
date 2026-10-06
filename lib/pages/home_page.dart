import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/notification_service.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/course_card.dart';
import '../widgets/week_picker.dart';
import 'login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// 让用户选「现在是第几周」，App 据此反推开学日期、之后自动顺延
  Future<void> _pickWeek(int current) async {
    final maxWeek = Store.schedule.maxWeek;
    final ok = await showWeekPicker(context, maxWeek: maxWeek, current: current);
    if (ok && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Store.version,
      builder: (_, __, ___) {
        final schedule = Store.schedule;
        final now = DateTime.now();
        final week = Store.weekOf(now);
        final today = schedule.dayCourses(now.weekday, week);

        return Scaffold(
          appBar: AppBar(title: const Text('fafu课程表')),
          body: ListView(
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
                ],
              ),
              const SizedBox(height: 12),
              if (today.isEmpty)
                _empty(schedule.courses.isEmpty)
              else
                ...today.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CourseCard(course: c, highlight: _isNext(c, now)),
                    )),
            ],
          ),
        );
      },
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
              const Text(
                '同学，你好',
                style: TextStyle(
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
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _empty(bool noCourses) {
    final now = DateTime.now();
    final isWeekend = now.weekday > 5;
    final notLoggedIn = noCourses && !Store.hasCookie;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 46, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
              notLoggedIn
                  ? Icons.login_outlined
                  : noCourses
                      ? Icons.edit_note_outlined
                      : (isWeekend
                          ? Icons.weekend_outlined
                          : Icons.free_breakfast_outlined),
              size: 46,
              color: AppColors.primaryLight),
          const SizedBox(height: 12),
          Text(
              notLoggedIn
                  ? '还没有登录\n登录学校统一身份认证，一键同步课表'
                  : noCourses
                      ? '还没有录入课程\n去「课程」页添加你的课表吧'
                      : (isWeekend ? '周末愉快，今天没有课' : '今天没有课，好好休息'),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: AppColors.textSub, fontSize: 14, height: 1.6)),
          if (notLoggedIn) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LoginPage(
                    onImported: (s) async {
                      await NotificationService.reschedule(s);
                    },
                  ),
                ),
              ),
              icon: const Icon(Icons.login, size: 18),
              label: const Text('去登录'),
            ),
          ],
        ],
      ),
    );
  }
}
