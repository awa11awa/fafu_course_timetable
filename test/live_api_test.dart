// ignore_for_file: avoid_print
//
// 一次性联调脚本（不参与发布）：用真实的 CAS 会话 Cookie 跑一遍
// TimetableApi 的全部接口，确认 Cookie/JWT/参数格式/解析都没问题。
//   NGXCAS 值从 /tmp/ngxcas.txt 读取
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/services/timetable_api.dart';

void main() {
  test('live: Cookie 换 JWT + 整学期课表', () async {
    final f = File('/tmp/ngxcas.txt');
    if (!f.existsSync()) {
      print('跳过：没有 /tmp/ngxcas.txt');
      return;
    }
    final cookie = 'NGXCAS=${f.readAsStringSync().trim()}';

    final token = await TimetableApi.fetchTokenWithCookie(cookie);
    print('JWT 用户=${TimetableApi.jwtField(token, 'user_name')} '
        '学号=${TimetableApi.jwtField(token, 'user_no')}');

    final api = TimetableApi(token: token, cookie: cookie);

    final info = await api.weekInfo();
    print('周次: ${info.schoolYear} 第${info.semester}学期 '
        '当前第${info.weekIndex}周 开学=${info.termStartDate}');

    final weeks = await api.weekList('2026-09-18');
    print('教学周数=${weeks.length}');

    final sw = Stopwatch()..start();
    final courses = await api.fetchSemester(
        info: info, onProgress: (d, t) => print('  进度 $d/$t'));
    sw.stop();
    print('整学期课程=${courses.length} 条  耗时=${sw.elapsedMilliseconds}ms');
    for (final c in courses) {
      print('  ${c.weekdayShort} ${c.periodText} ${c.name} | ${c.teacher} | '
          '${c.place} | ${c.weeksText} | 时间=${c.timeRange}');
    }

    // 按周看（界面的「课表 / 今日」就是这么查的）
    final sched = Schedule(
      studentId: 'x',
      studentName: 'x',
      year: info.schoolYear,
      term: info.semester,
      fetchedAt: DateTime.now(),
      courses: courses,
    );
    for (final w in [1, 3, 4, 5]) {
      final m = sched.weekCourses(w);
      final n = m.values.fold<int>(0, (a, b) => a + b.length);
      print('第$w周 共$n 节: ${m.entries.where((e) => e.value.isNotEmpty).map((e) =>
          "${Course.weekdayNames[e.key - 1]}×${e.value.length}").join(' ')}');
    }

    // 刷新用的对比（当前周）
    final fresh = await api.weekLessons(info.schoolYear, info.semester, info.weekIndex);
    final a = {for (final c in fresh) '${c.name}|${c.weekday}|${c.periods.join(",")}|${c.place}'};
    final b = {for (final c in sched.courses.where((c) => c.activeInWeek(info.weekIndex)))
        '${c.name}|${c.weekday}|${c.periods.join(",")}|${c.place}'};
    print('当前周对比: 新=${a.length} 缓存=${b.length} 一致=${a.length == b.length && a.containsAll(b)}');

    expect(token.isNotEmpty, true);
    expect(courses, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
