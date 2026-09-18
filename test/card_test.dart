// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/widgets/course_card.dart';

const c = Course(
  name: '高等数学A1', teacher: '官明友', place: '创106',
  weekday: 1, periods: [1, 2], weeksRaw: '第2-17周', weekType: '每周',
  startWeek: 2, endWeek: 17,
);

void main() {
  testWidgets('CourseCard 放在 ListView 里应当能正常布局并显示', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [CourseCard(course: c)])),
    ));
    await tester.pumpAndSettle();

    final ex = tester.takeException();
    print('布局异常: ${ex ?? "无 ✓"}');
    print('找到课程名: ${find.text('高等数学A1').evaluate().length} 个');
    print('找到节次:   ${find.text('第1,2节').evaluate().length} 个');

    expect(ex, isNull, reason: '不应有布局异常');
    expect(find.text('高等数学A1'), findsOneWidget);
    expect(find.text('第1,2节'), findsOneWidget);
  });

  testWidgets('高亮态（即将上课）也要正常', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [CourseCard(course: c, highlight: true)])),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('即将上课'), findsOneWidget);
  });
}
