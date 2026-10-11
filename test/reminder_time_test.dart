import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/models/lesson_time.dart';
import 'package:fafu_kebiao/services/reminder_planner.dart';
import 'package:fafu_kebiao/services/store.dart';

Course course(List<int> periods, {String campus = ''}) => Course(
  name: 'Fixture course', teacher: '', place: '', weekday: 1,
  periods: periods, weeksRaw: '第7周', weekType: '每周', startWeek: 7, endWeek: 7,
  campusCode: campus,
);

Map<String, dynamic> campusFixture() => {
  'campusCode': '0',
  'userNo': 'fictional-private-value-not-to-be-stored',
  'campusLessonPeriods': [
    {'campusCode': '0', 'lessonPeriods': [
      {'lessonNo': 1, 'beginTime': '08:00', 'endTime': '08:45'},
      {'lessonNo': 2, 'beginTime': '08:50', 'endTime': '09:35'},
      {'lessonNo': 3, 'beginTime': '09:55', 'endTime': '10:40'},
      {'lessonNo': 4, 'beginTime': '10:45', 'endTime': '11:30'},
    ]},
    {'campusCode': '5', 'lessonPeriods': [
      {'lessonNo': 1, 'beginTime': '08:20', 'endTime': '09:05'},
      {'lessonNo': 2, 'beginTime': '09:10', 'endTime': '09:55'},
      {'lessonNo': 3, 'beginTime': '10:15', 'endTime': '11:00'},
      {'lessonNo': 4, 'beginTime': '11:05', 'endTime': '11:50'},
    ]},
  ],
};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    await Store.saveTermStart(DateTime(2026, 8, 30));
  });

  test('legacy cached courses match all three school screenshot time ranges', () {
    for (final entry in {
      [1, 2]: '08:00-09:35', [3, 4]: '09:55-11:30', [6, 7]: '14:00-15:35',
    }.entries) {
      final restored = Course.fromJson(course(entry.key).toJson()..remove('campusCode'));
      expect(restored.timeRange, entry.value);
    }
  });

  test('campus tables remain separate and persist across process restart', () async {
    final tables = SchoolLessonTimes.fromJson(campusFixture());
    expect(jsonEncode(tables.toJson()), isNot(contains('fictional-private-value')));
    await Store.saveLessonTimes(tables);
    PeriodTime.restore(null);
    await Store.init();
    expect(course([1, 2]).timeRange, '08:00-09:35');
    expect(Course.fromJson(course([1, 2], campus: '5').toJson()).timeRange, '08:20-09:55');
  });

  test('selected campus changes display and reminder from the same saved table', () async {
    final json = campusFixture()..['campusCode'] = '5';
    await Store.saveLessonTimes(SchoolLessonTimes.fromJson(json));
    final c = course([3, 4]);
    final reminder = ReminderPlanner.upcoming(Schedule(courses: [c]),
        from: DateTime.utc(2026, 10, 11, 23), days: 0, leadMinutes: 10).single;
    expect(c.timeRange, '10:15-11:50');
    expect(reminder.classStart.toUtc(), DateTime.utc(2026, 10, 12, 2, 15));
    expect(reminder.when.toUtc(), DateTime.utc(2026, 10, 12, 2, 5));
    expect(reminder.body, contains(c.timeRange));
  });

  test('reminders use school timezone even when input instant is in UTC', () {
    final c = course([3, 4]);
    final items = ReminderPlanner.upcoming(Schedule(courses: [c]),
      from: DateTime.utc(2026, 10, 11, 23), days: 0, leadMinutes: 10);
    expect(items.single.week, 7);
    expect(items.single.classStart.toUtc(), DateTime.utc(2026, 10, 12, 1, 55));
    expect(items.single.when.toUtc(), DateTime.utc(2026, 10, 12, 1, 45));
    expect(ReminderPlanner.upcoming(Schedule(courses: [c]),
      from: DateTime.utc(2026, 10, 12, 1, 46), days: 0), isEmpty);
  });

  test('malformed time rows cannot overwrite a valid saved timetable', () async {
    await Store.saveLessonTimes(SchoolLessonTimes.fromJson(campusFixture()));
    await Store.saveLessonTimes(SchoolLessonTimes.fromJson({
      'campusLessonPeriods': [{'campusCode': '0', 'lessonPeriods': [
        {'lessonNo': 1, 'beginTime': '25:00', 'endTime': '25:45'},
        {'lessonNo': 2, 'beginTime': '09:35', 'endTime': '08:50'},
      ]}],
    }));
    expect(course([1, 2]).timeRange, '08:00-09:35');
  });
}
