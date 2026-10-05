import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/notification_service.dart';
import '../services/store.dart';
import '../theme.dart';
import 'course_edit_page.dart';

/// 课程管理：手动录入 / 编辑 / 删除课程
class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key});

  Future<void> _add(BuildContext context) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CourseEditPage()),
    );
    if (saved == true && context.mounted) {
      await NotificationService.reschedule(Store.schedule);
    }
  }

  Future<void> _edit(BuildContext context, int index, Course course) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => CourseEditPage(index: index, course: course)),
    );
    if (saved == true && context.mounted) {
      await NotificationService.reschedule(Store.schedule);
    }
  }

  Future<void> _delete(BuildContext context, int index, Course course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${course.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除',
                  style: TextStyle(color: Color(0xFFD4380D)))),
        ],
      ),
    );
    if (ok != true) return;
    final courses = [...Store.schedule.courses]..removeAt(index);
    await Store.saveSchedule(Schedule(courses: courses));
    await NotificationService.reschedule(Store.schedule);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Store.version,
      builder: (_, __, ___) {
        final courses = Store.schedule.courses;
        // 记下每门课在原列表中的下标，供编辑/删除使用
        final indexed = courses.asMap().entries.toList();

        return Scaffold(
          appBar: AppBar(title: const Text('课程管理')),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            onPressed: () => _add(context),
            child: const Icon(Icons.add),
          ),
          body: courses.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_note_outlined,
                          size: 52, color: AppColors.primaryLight),
                      const SizedBox(height: 14),
                      const Text('还没有录入课程',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text)),
                      const SizedBox(height: 6),
                      const Text('点右下角 + 手动添加你的课程',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textFaint)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                  children: [
                    for (final d in Course.weekOrder)
                      ..._dayGroup(context, d, indexed),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _dayGroup(
      BuildContext context, int weekday, List<MapEntry<int, Course>> indexed) {
    final items =
        indexed.where((e) => e.value.weekday == weekday).toList();
    if (items.isEmpty) return [];
    items.sort((a, b) {
      final pa = a.value.periods.isEmpty ? 99 : a.value.periods.first;
      final pb = b.value.periods.isEmpty ? 99 : b.value.periods.first;
      return pa.compareTo(pb);
    });
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2, top: 6),
        child: Text(Course.weekdayNames[weekday - 1],
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.primaryDark)),
      ),
      ...items.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _courseTile(context, e.key, e.value),
          )),
    ];
  }

  Widget _courseTile(BuildContext context, int index, Course c) {
    final sub = [
      c.periodText,
      if (c.place.isNotEmpty) c.place,
      if (c.teacher.isNotEmpty) c.teacher,
      c.weeksText + (c.weekType == '每周' ? '' : '·${c.weekType}'),
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 14, right: 6),
        title: Text(c.name,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(sub,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSub)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.textSub),
              onPressed: () => _edit(context, index, c),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: Color(0xFFD4380D)),
              onPressed: () => _delete(context, index, c),
            ),
          ],
        ),
        onTap: () => _edit(context, index, c),
      ),
    );
  }
}
