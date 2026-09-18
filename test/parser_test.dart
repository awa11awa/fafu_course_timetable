// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fafu_kebiao/services/schedule_parser.dart';

void main() {
  test('用真实课表页测试解析器', () {
    final html = utf8.decode(File('test/kb_real.html').readAsBytesSync());
    final (courses, year, term) = ScheduleParser.parse(html);
    print('学年=$year 学期=$term  课程数=${courses.length}');
    final bad = courses.where((c) => c.name.isEmpty || c.periods.isEmpty).toList();
    print('异常记录数(无名称或节次)=${bad.length}');
    for (final c in courses.take(6)) {
      print('  ${c.weekdayName} ${c.periodText} | ${c.name} | ${c.teacher} | ${c.place} | ${c.weeksText}');
    }
    // 校验周课表能组织起来
    final week = {for (var d = 1; d <= 7; d++) d: courses.where((c) => c.weekday == d).length};
    print('各天课程数: $week');
    expect(courses.isNotEmpty, true);
    expect(bad.isEmpty, true, reason: '不应有缺名称或缺节次的记录');
  });
}
