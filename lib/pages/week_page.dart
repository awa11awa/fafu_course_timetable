import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/store.dart';
import '../widgets/course_card.dart';
import '../theme.dart';

class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  Schedule? _schedule;
  late int _week;
  bool _gridView = true;

  static const double _rowH = 58;
  static const double _timeColW = 40;

  @override
  void initState() {
    super.initState();
    _schedule = Store.schedule;
    _week = Store.weekOf(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final s = _schedule;
    return Scaffold(
      appBar: AppBar(
        title: const Text('周课表'),
        actions: [
          IconButton(
            tooltip: _gridView ? '切换列表' : '切换课表',
            onPressed: () => setState(() => _gridView = !_gridView),
            icon: Icon(_gridView ? Icons.view_list_outlined : Icons.grid_view),
          ),
        ],
      ),
      body: s == null
          ? const Center(
              child: Text('暂无课表数据，请先在「今日」页刷新',
                  style: TextStyle(color: AppColors.textSub)))
          : Column(
              children: [
                _weekBar(s),
                const Divider(height: 1),
                Expanded(
                  child: _gridView ? _tableView(s, _week) : _listView(s, _week),
                ),
              ],
            ),
    );
  }

  // ---------------- 周次选择条 ----------------
  Widget _weekBar(Schedule s) {
    final maxWeek = s.maxWeek;
    final thisWeek = Store.weekOf(DateTime.now());
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _week > 1 ? () => setState(() => _week--) : null,
            icon: const Icon(Icons.chevron_left),
            color: AppColors.primary,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _pickWeek(maxWeek),
              child: Column(
                children: [
                  Text('第 $_week 周',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    _week == thisWeek ? '本周' : '点击选择周次',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textFaint),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed:
                _week < maxWeek ? () => setState(() => _week++) : null,
            icon: const Icon(Icons.chevron_right),
            color: AppColors.primary,
          ),
          if (_week != thisWeek)
            TextButton(
              onPressed: () => setState(() => _week = thisWeek),
              child: const Text('回到本周'),
            ),
        ],
      ),
    );
  }

  void _pickWeek(int maxWeek) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('选择周次',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            SizedBox(
              height: 260,
              child: GridView.count(
                crossAxisCount: 5,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: List.generate(maxWeek, (i) {
                  final w = i + 1;
                  final active = w == _week;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _week = w);
                      Navigator.pop(context);
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.primaryFaint,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('$w',
                          style: TextStyle(
                            color: active ? Colors.white : AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  // ---------------- 列表视图 ----------------
  Widget _listView(Schedule s, int week) {
    final days = s.weekCourses(week);
    final hasAny = days.values.any((e) => e.isNotEmpty);
    if (!hasAny) {
      return const Center(
        child: Text('本周没有课程', style: TextStyle(color: AppColors.textSub)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        for (var d = 1; d <= 7; d++)
          if (days[d]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Text(Course.weekdayNames[d - 1],
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.primaryDark)),
            ),
            ...days[d]!.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CourseCard(course: c),
                )),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  // ---------------- 课表网格视图 ----------------
  Widget _tableView(Schedule s, int week) {
    final days = s.weekCourses(week);
    var maxPeriod = 12;
    for (final list in days.values) {
      for (final c in list) {
        if (c.periods.isNotEmpty && c.periods.last > maxPeriod) {
          maxPeriod = c.periods.last;
        }
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // 星期表头
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                const SizedBox(width: _timeColW),
                for (var d = 1; d <= 7; d++)
                  Expanded(
                    child: Column(
                      children: [
                        Text(Course.weekdayNames[d - 1].substring(2),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: d == DateTime.now().weekday &&
                                      week == Store.weekOf(DateTime.now())
                                  ? AppColors.primary
                                  : AppColors.textSub,
                            )),
                        const SizedBox(height: 2),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: d == DateTime.now().weekday &&
                                    week == Store.weekOf(DateTime.now())
                                ? AppColors.primary
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _timeColW,
                  child: Column(
                    children: List.generate(
                      maxPeriod,
                      (i) => SizedBox(
                        height: _rowH,
                        child: Center(
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textFaint)),
                        ),
                      ),
                    ),
                  ),
                ),
                for (var d = 1; d <= 7; d++)
                  Expanded(child: _dayColumn(days[d]!, maxPeriod, week)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayColumn(List<Course> courses, int maxPeriod, int week) {
    final sorted = [...courses]
      ..sort((a, b) => (a.periods.isEmpty ? 99 : a.periods.first)
          .compareTo(b.periods.isEmpty ? 99 : b.periods.first));

    final children = <Widget>[];
    var cursor = 1;
    for (final c in sorted) {
      if (c.periods.isEmpty) continue;
      final start = c.periods.first;
      final span = c.periods.length;
      if (start > cursor) {
        for (var i = cursor; i < start; i++) {
          children.add(SizedBox(height: _rowH));
        }
      }
      children.add(Container(
        height: _rowH * span - 2,
        margin: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCFE1F8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                c.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            if (c.place.isNotEmpty)
              Text(
                c.place,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9.5, color: AppColors.primaryMid),
              ),
          ],
        ),
      ));
      cursor = start + span;
    }
    while (cursor <= maxPeriod) {
      children.add(SizedBox(height: _rowH));
      cursor++;
    }

    return Column(children: children);
  }
}
