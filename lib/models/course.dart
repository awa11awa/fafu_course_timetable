import '../theme.dart';

/// 单条课程安排
class Course {
  final String name;
  final String teacher;
  final String place;
  final int weekday; // 1=周一 ... 7=周日
  final List<int> periods; // 节次，如 [1,2]
  final String weeksRaw; // 展示用，如 "第1-16周"
  final String weekType; // 每周 / 单周 / 双周
  final int? startWeek;
  final int? endWeek;

  const Course({
    required this.name,
    required this.teacher,
    required this.place,
    required this.weekday,
    required this.periods,
    required this.weeksRaw,
    required this.weekType,
    this.startWeek,
    this.endWeek,
  });

  static const List<String> weekdayNames = [
    '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日',
  ];

  /// 一周的显示顺序：学校教学周从**周日**开始（周日 → 周六）
  static const List<int> weekOrder = [7, 1, 2, 3, 4, 5, 6];

  String get weekdayName =>
      (weekday >= 1 && weekday <= 7) ? weekdayNames[weekday - 1] : '';

  String get weekdayShort => weekdayName.replaceFirst('星期', '周');

  String get periodText => periods.isEmpty ? '' : '第${periods.join(',')}节';

  String get startTime => periods.isEmpty ? '' : (PeriodTime.start[periods.first] ?? '');

  String get endTime => periods.isEmpty ? '' : (PeriodTime.end[periods.last] ?? '');

  String get timeRange =>
      (startTime.isEmpty || endTime.isEmpty) ? '' : '$startTime-$endTime';

  /// 该课程在第 [week] 周是否上课
  bool activeInWeek(int week) {
    final s = startWeek, e = endWeek;
    if (s != null && week < s) return false;
    if (e != null && week > e) return false;
    if (weekType == '单周' && week.isEven) return false;
    if (weekType == '双周' && week.isOdd) return false;
    return true;
  }

  /// 展示用周次文本
  String get weeksText {
    if (weeksRaw.isNotEmpty) return weeksRaw;
    if (startWeek != null && endWeek != null) {
      return startWeek == endWeek ? '第$startWeek周' : '第$startWeek-$endWeek周';
    }
    return '';
  }

  /// 提醒用的唯一键
  String get key => '$name|$weekday|${periods.join(",")}|$weeksRaw|$place|$teacher';

  /// 手动录入时由起止周生成展示文本
  static String buildWeeksRaw(int start, int end) =>
      start == end ? '第$start周' : '第$start-$end周';

  Map<String, dynamic> toJson() => {
        'name': name,
        'teacher': teacher,
        'place': place,
        'weekday': weekday,
        'periods': periods,
        'weeksRaw': weeksRaw,
        'weekType': weekType,
        'startWeek': startWeek,
        'endWeek': endWeek,
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        name: (j['name'] ?? '') as String,
        teacher: (j['teacher'] ?? '') as String,
        place: (j['place'] ?? '') as String,
        weekday: (j['weekday'] ?? 1) as int,
        periods: ((j['periods'] ?? []) as List).map((e) => e as int).toList(),
        weeksRaw: (j['weeksRaw'] ?? '') as String,
        weekType: (j['weekType'] ?? '每周') as String,
        startWeek: j['startWeek'] as int?,
        endWeek: j['endWeek'] as int?,
      );
}

/// 本机保存的整份课表（手动录入，或从学校统一身份认证同步）
class Schedule {
  final List<Course> courses;

  /// 同步来的元数据（手动录入时为空）
  final String studentId;
  final String studentName;
  final String year; // 如 2026-2027
  final String term; // 1/2/3
  final DateTime? fetchedAt;

  const Schedule({
    required this.courses,
    this.studentId = '',
    this.studentName = '',
    this.year = '',
    this.term = '',
    this.fetchedAt,
  });

  const Schedule.empty() : this(courses: const []);

  /// 是否从学校同步过
  bool get isSynced => year.isNotEmpty;

  String get termLabel => year.isEmpty ? '' : '$year学年第$term学期';

  /// 某天(weekday 1-7)在第 [week] 周的课程，按节次排序
  List<Course> dayCourses(int weekday, int week) {
    final list = courses
        .where((c) => c.weekday == weekday && c.activeInWeek(week))
        .toList();
    list.sort((a, b) {
      final pa = a.periods.isEmpty ? 99 : a.periods.first;
      final pb = b.periods.isEmpty ? 99 : b.periods.first;
      if (pa != pb) return pa.compareTo(pb);
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// 整周(周一~周日)的课程
  Map<int, List<Course>> weekCourses(int week) =>
      {for (var d = 1; d <= 7; d++) d: dayCourses(d, week)};

  /// 该学期出现过的最大周次
  int get maxWeek {
    var m = 0;
    for (final c in courses) {
      if (c.endWeek != null && c.endWeek! > m) m = c.endWeek!;
      if (c.startWeek != null && c.endWeek == null && c.startWeek! > m) {
        m = c.startWeek!;
      }
    }
    return m == 0 ? 20 : m;
  }

  Map<String, dynamic> toJson() => {
        'courses': courses.map((c) => c.toJson()).toList(),
        'studentId': studentId,
        'studentName': studentName,
        'year': year,
        'term': term,
        'fetchedAt': fetchedAt?.millisecondsSinceEpoch,
      };

  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
        courses: ((j['courses'] ?? []) as List)
            .map((e) => Course.fromJson(e as Map<String, dynamic>))
            .toList(),
        studentId: (j['studentId'] ?? '') as String,
        studentName: (j['studentName'] ?? '') as String,
        year: (j['year'] ?? '') as String,
        term: (j['term'] ?? '') as String,
        fetchedAt: j['fetchedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['fetchedAt'] as num).toInt()),
      );
}
