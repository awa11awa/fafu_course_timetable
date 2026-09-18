// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fafu_kebiao/models/course.dart';
import 'package:fafu_kebiao/services/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('一周按 周日→周六 显示', () {
    expect(Course.weekOrder, [7, 1, 2, 3, 4, 5, 6]);
    // 表头取 weekdayNames[d-1] 的第三个字 → 日 一 二 三 四 五 六
    final heads = Course.weekOrder
        .map((d) => Course.weekdayNames[d - 1].substring(2))
        .join();
    expect(heads, '日一二三四五六');
    // 接口的 weekday 语义不变：1=周一 … 7=周日
    expect(Course.weekdayNames[0], '星期一');
    expect(Course.weekdayNames[6], '星期日');
  });

  test('教学周从周日算起（与教务接口一致）', () async {
    await Store.init();
    // 2026-09-18 是周五，接口说当时是第 3 周
    await Store.setCurrentWeek(3, DateTime(2026, 9, 18));
    expect(Store.termStart, DateTime(2026, 8, 30)); // 第 1 周的周日

    expect(Store.weekOf(DateTime(2026, 9, 13)), 3); // 周日已经是第 3 周
    expect(Store.weekOf(DateTime(2026, 9, 18)), 3); // 周五
    expect(Store.weekOf(DateTime(2026, 9, 19)), 3); // 周六
    expect(Store.weekOf(DateTime(2026, 9, 20)), 4); // 下周日进入第 4 周
    expect(Store.weekOf(DateTime(2026, 9, 6)), 2); // 第 2 周周日
  });

  test('用接口给的开学日期校准', () async {
    await Store.init();
    await Store.applyWeekInfo(3, '2026-08-30 00:00:00');
    expect(Store.termStart, DateTime(2026, 8, 30));
    expect(Store.weekOf(DateTime(2026, 9, 13)), 3);
  });

  test('接口没给日期时退回用周次反推', () async {
    await Store.init();
    await Store.applyWeekInfo(3, '');
    expect(Store.termStart, isNotNull);
    expect(Store.weekOf(DateTime.now()), 3);
  });

  test('课程按周次区间生效', () {
    const c = Course(
      name: '高等数学A1',
      teacher: '官明友',
      place: '创106',
      weekday: 1,
      periods: [1, 2],
      weeksRaw: '第2-17周',
      weekType: '每周',
      startWeek: 2,
      endWeek: 17,
    );
    expect(c.activeInWeek(1), false);
    expect(c.activeInWeek(2), true);
    expect(c.activeInWeek(17), true);
    expect(c.activeInWeek(18), false);
  });
}
