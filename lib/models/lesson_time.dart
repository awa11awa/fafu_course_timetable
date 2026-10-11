/// Only campus identifiers and lesson times are retained from school config.
class LessonPeriod {
  final String begin;
  final String end;
  const LessonPeriod(this.begin, this.end);

  static String normalize(Object? value) {
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})(?::\d{2})?$')
        .firstMatch((value ?? '').toString().trim());
    if (match == null) return '';
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    if (hour > 23 || minute > 59) return '';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class SchoolLessonTimes {
  final String campusCode;
  final Map<String, Map<int, LessonPeriod>> campuses;
  const SchoolLessonTimes(this.campusCode, this.campuses);

  factory SchoolLessonTimes.fromJson(Map<String, dynamic> json) {
    final campuses = <String, Map<int, LessonPeriod>>{};
    for (final raw in json['campusLessonPeriods'] as List? ?? const []) {
      if (raw is! Map || raw['campusCode'] == null) continue;
      final periods = <int, LessonPeriod>{};
      for (final row in raw['lessonPeriods'] as List? ?? const []) {
        if (row is! Map) continue;
        final number = int.tryParse('${row['lessonNo']}');
        final begin = LessonPeriod.normalize(row['beginTime']);
        final end = LessonPeriod.normalize(row['endTime']);
        if (number == null || number < 1 || number > 24 ||
            begin.isEmpty || end.isEmpty || begin.compareTo(end) >= 0) {
          continue;
        }
        periods[number] = LessonPeriod(begin, end);
      }
      if (periods.isNotEmpty) campuses['${raw['campusCode']}'] = periods;
    }
    final requested = (json['campusCode'] ?? '0').toString();
    final selected = campuses.containsKey(requested) ? requested :
        campuses.containsKey('0') ? '0' : campuses.keys.firstOrNull ?? '0';
    return SchoolLessonTimes(selected, campuses);
  }

  Map<String, dynamic> toJson() => {
    'campusCode': campusCode,
    'campusLessonPeriods': [for (final campus in campuses.entries) {
      'campusCode': campus.key,
      'lessonPeriods': [for (final row in campus.value.entries) {
        'lessonNo': row.key, 'beginTime': row.value.begin, 'endTime': row.value.end,
      }],
    }],
  };
}

/// Defaults match the school's Cangshan campus config captured in October 2026.
/// A successful sync replaces these with the school's campus-specific times.
class PeriodTime {
  static const _defaults = <int, LessonPeriod>{
    1: LessonPeriod('08:00', '08:45'), 2: LessonPeriod('08:50', '09:35'),
    3: LessonPeriod('09:55', '10:40'), 4: LessonPeriod('10:45', '11:30'),
    5: LessonPeriod('11:35', '12:20'), 6: LessonPeriod('14:00', '14:45'),
    7: LessonPeriod('14:50', '15:35'), 8: LessonPeriod('15:50', '16:35'),
    9: LessonPeriod('16:40', '17:25'), 10: LessonPeriod('18:25', '19:10'),
    11: LessonPeriod('19:15', '20:00'), 12: LessonPeriod('20:05', '20:50'),
  };
  static SchoolLessonTimes? _school;
  static void restore(SchoolLessonTimes? value) => _school = value;
  static Map<int, LessonPeriod> _forCampus(String code) =>
      _school?.campuses[code.isEmpty ? _school!.campusCode : code] ?? _defaults;
  static String startOf(int period, [String campus = '']) =>
      _forCampus(campus)[period]?.begin ?? _defaults[period]?.begin ?? '';
  static String endOf(int period, [String campus = '']) =>
      _forCampus(campus)[period]?.end ?? _defaults[period]?.end ?? '';
  static Map<int, String> get start => {
    for (final period in _defaults.keys) period: startOf(period),
  };
  static Map<int, String> get end => {
    for (final period in _defaults.keys) period: endOf(period),
  };
}
