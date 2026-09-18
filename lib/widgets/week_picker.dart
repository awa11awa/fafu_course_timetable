import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/store.dart';
import '../theme.dart';

/// 让用户选「现在是第几周」，App 据此反推开学日期、之后自动顺延。
///
/// 为什么不自动判断：正方课表页面里只有学年/学期两个下拉，**没有当前周次信息**，
/// 所以只能由用户告知一次。
Future<bool> showWeekPicker(
  BuildContext context, {
  required int maxWeek,
  int? current,
}) async {
  final picked = await showModalBottomSheet<int>(
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
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('现在是第几周？',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text('教务系统不提供当前周次，需要你选一次；之后会自动按周往后走。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
          ),
          SizedBox(
            height: 280,
            child: GridView.count(
              crossAxisCount: 5,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: List.generate(maxWeek, (i) {
                final w = i + 1;
                final active = w == current;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, w),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          active ? AppColors.primary : AppColors.primaryFaint,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('$w',
                        style: TextStyle(
                          color:
                              active ? Colors.white : AppColors.primaryDark,
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

  if (picked == null) return false;
  await Store.setCurrentWeek(picked);
  return true;
}

/// 今天在第 [week] 周有几节课（用于提示）
int countOnWeekday(Schedule? s, int weekday, int week) =>
    s == null ? 0 : s.dayCourses(weekday, week).length;

/// 未设置周次时的提示条
class WeekHintBanner extends StatelessWidget {
  final VoidCallback onTap;
  const WeekHintBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFE0A3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Color(0xFFB26A00)),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                '还没设置当前周次，显示的课程可能不准\n点这里选一下「现在是第几周」',
                style: TextStyle(
                    fontSize: 12.5, height: 1.45, color: Color(0xFF8A5200)),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB26A00)),
          ],
        ),
      ),
    );
  }
}
