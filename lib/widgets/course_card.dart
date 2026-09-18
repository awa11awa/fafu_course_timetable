import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme.dart';

class CourseCard extends StatelessWidget {
  final Course course;
  final bool highlight;
  final int? week;

  const CourseCard({
    super.key,
    required this.course,
    this.highlight = false,
    this.week,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? AppColors.primary : AppColors.divider,
          width: highlight ? 1.4 : 1,
        ),
      ),
      // 坑：Row 用 CrossAxisAlignment.stretch 时，子项会被要求撑满交叉轴（高度）。
      // 而卡片放在 ListView 里，高度是无界的 —— 子项被要求撑到无限高，布局会失败，
      // 结果就是"共 1 节"但卡片完全不显示。用 IntrinsicHeight 先给行定出实际高度。
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // 左侧蓝色时间条
          Container(
            width: 74,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: highlight ? AppColors.primary : AppColors.primaryLight,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                bottomLeft: Radius.circular(13),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  course.periodText,
                  style: TextStyle(
                    color: highlight ? Colors.white : AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  course.timeRange,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: highlight
                        ? const Color(0xE6FFFFFF)
                        : AppColors.primaryMid,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          course.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      if (highlight)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('即将上课',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.primaryDark)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  _line(Icons.place_outlined,
                      course.place.isEmpty ? '地点待定' : course.place),
                  const SizedBox(height: 3),
                  _line(Icons.person_outline,
                      course.teacher.isEmpty ? '教师待定' : course.teacher),
                  if (course.weeksText.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _line(Icons.date_range_outlined,
                        '${course.weeksText}${course.weekType == '每周' ? '' : ' · ${course.weekType}'}'),
                  ],
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 13.5, color: AppColors.textFaint),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSub),
            ),
          ),
        ],
      );
}
