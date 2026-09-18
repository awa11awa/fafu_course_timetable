import '../models/course.dart';
import '../theme.dart';
import 'store.dart';

class ReminderItem {
  final Course course;
  final DateTime when; // 提醒触发时间
  final DateTime classStart;
  final int week;

  ReminderItem({
    required this.course,
    required this.when,
    required this.classStart,
    required this.week,
  });

  String get body {
    final t = course.timeRange.isEmpty ? course.periodText : course.timeRange;
    final place = course.place.isEmpty ? '' : ' · ${course.place}';
    return '$t$place${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}';
  }
}

/// 根据课表算出未来若干天内所有需要提醒的上课时刻
class ReminderPlanner {
  static List<ReminderItem> upcoming(
    Schedule schedule, {
    int days = 14,
    int leadMinutes = 10,
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    final items = <ReminderItem>[];
    final remindOnly = Store.remindCourses;

    for (var offset = 0; offset <= days; offset++) {
      final date = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
      final week = Store.weekOf(date);
      final weekday = date.weekday; // 1=周一

      for (final c in schedule.courses) {
        if (c.weekday != weekday) continue;
        if (!c.activeInWeek(week)) continue;
        if (c.periods.isEmpty) continue;
        if (remindOnly.isNotEmpty && !remindOnly.contains(c.key)) continue;

        final startText = PeriodTime.start[c.periods.first];
        if (startText == null) continue;
        final parts = startText.split(':');
        final classStart = DateTime(date.year, date.month, date.day,
            int.parse(parts[0]), int.parse(parts[1]));
        final when = classStart.subtract(Duration(minutes: leadMinutes));
        if (when.isBefore(now)) continue;

        items.add(ReminderItem(
          course: c,
          when: when,
          classStart: classStart,
          week: week,
        ));
      }
    }
    items.sort((a, b) => a.when.compareTo(b.when));
    return items;
  }
}
