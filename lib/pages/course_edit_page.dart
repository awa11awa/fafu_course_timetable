import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/course.dart';
import '../services/store.dart';
import '../theme.dart';

/// 添加 / 编辑课程
class CourseEditPage extends StatefulWidget {
  /// 传 index + course 表示编辑；都不传表示新增
  final int? index;
  final Course? course;

  const CourseEditPage({super.key, this.index, this.course});

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

class _CourseEditPageState extends State<CourseEditPage> {
  final _nameCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();

  int _weekday = 1;
  final Set<int> _periods = {};
  int _startWeek = 1;
  int _endWeek = 16;
  String _weekType = '每周';

  bool get _isEdit => widget.course != null;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    if (c != null) {
      _nameCtrl.text = c.name;
      _teacherCtrl.text = c.teacher;
      _placeCtrl.text = c.place;
      _weekday = c.weekday;
      _periods.addAll(c.periods);
      _startWeek = c.startWeek ?? 1;
      _endWeek = c.endWeek ?? 16;
      _weekType = c.weekType;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _placeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _tip('请填写课程名称');
      return;
    }
    if (_periods.isEmpty) {
      _tip('请选择上课节次');
      return;
    }
    if (_startWeek > _endWeek) {
      _tip('开始周不能晚于结束周');
      return;
    }

    final periods = _periods.toList()..sort();
    final course = Course(
      name: name,
      teacher: _teacherCtrl.text.trim(),
      place: _placeCtrl.text.trim(),
      weekday: _weekday,
      periods: periods,
      weeksRaw: Course.buildWeeksRaw(_startWeek, _endWeek),
      weekType: _weekType,
      startWeek: _startWeek,
      endWeek: _endWeek,
    );

    final courses = [...Store.schedule.courses];
    if (_isEdit) {
      courses[widget.index!] = course;
    } else {
      courses.add(course);
    }
    await Store.saveSchedule(Schedule(courses: courses));
    if (mounted) {
      _tip(_isEdit ? '已保存' : '已添加「$name」');
      Navigator.pop(context, true);
    }
  }

  void _tip(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? '编辑课程' : '添加课程')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _label('课程名称 *'),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(hintText: '如：高等数学'),
          ),
          const SizedBox(height: 14),
          _label('任课教师'),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(hintText: '选填'),
          ),
          const SizedBox(height: 14),
          _label('上课地点'),
          TextField(
            controller: _placeCtrl,
            decoration: const InputDecoration(hintText: '如：教3-201，选填'),
          ),
          const SizedBox(height: 18),
          _label('星期'),
          _card(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  _chip(
                    Course.weekdayNames[d - 1].replaceFirst('星期', '周'),
                    selected: _weekday == d,
                    onTap: () => setState(() => _weekday = d),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('节次（可多选）*'),
          _card(
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var p = 1; p <= 12; p++)
                  _chip(
                    '第$p节',
                    selected: _periods.contains(p),
                    onTap: () => setState(() {
                      if (_periods.contains(p)) {
                        _periods.remove(p);
                      } else {
                        _periods.add(p);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('上课周次'),
          _card(
            Column(
              children: [
                _weekStepper('开始周', _startWeek, (v) {
                  setState(() {
                    _startWeek = v;
                    if (_endWeek < _startWeek) _endWeek = _startWeek;
                  });
                }),
                const Divider(height: 1, indent: 4, endIndent: 4),
                _weekStepper('结束周', _endWeek, (v) {
                  setState(() {
                    _endWeek = v;
                    if (_startWeek > _endWeek) _startWeek = _endWeek;
                  });
                }),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _label('单双周'),
          _card(
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 2 ? 0 : 8),
                      child: _chip(
                        ['每周', '单周', '双周'][i],
                        selected: _weekType == ['每周', '单周', '双周'][i],
                        onTap: () => setState(
                            () => _weekType = ['每周', '单周', '双周'][i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          ElevatedButton(
            onPressed: _save,
            child: Text(_isEdit ? '保存' : '添加课程'),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSub)),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  Widget _chip(String text,
      {required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.primaryFaint,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.textSub,
          ),
        ),
      ),
    );
  }

  Widget _weekStepper(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14.5, color: AppColors.text)),
          const Spacer(),
          _stepBtn(Icons.remove, () {
            if (value > 1) onChanged(value - 1);
          }),
          SizedBox(
            width: 76,
            child: Text('第 $value 周',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark)),
          ),
          _stepBtn(Icons.add, () {
            if (value < 30) onChanged(value + 1);
          }),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primaryFaint,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.divider),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
      );
}
