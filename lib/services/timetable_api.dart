import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/course.dart';

/// 真正的课表数据源：「我的课表」微应用
///
/// 入口链路：
///   统一身份认证(CAS) → 网上办事服务大厅(ehall) → 「我的课表」
///   → https://task.fafu.edu.cn/timetable
///
/// 认证方式（2026-09 实测）：
///   * 网关(openresty)只认 CAS 会话 Cookie `NGXCAS`；
///     只带 JWT 不带 Cookie → 302 跳回登录页（返回 HTML，JSON 解析必失败）。
///   * 个人课表接口 `my/course/schedule/*` 还额外要求 `Authorization: Bearer <JWT>`。
///   * JWT 用 `GET /he/token`（带 Cookie）换取，有效期只有 1 小时 → 过期自动续。
///
/// 接口特性（踩过的坑）：
///   * `day/list` 忽略 dateAt，永远返回"当天"的课 → 不能用来抓整学期；
///   * `v2/week/list` 才是按周取数，但它每天会把「本学期全部课程花名册」混在
///     一起返回（这些行没有 startLesson），必须靠 startLesson 过滤掉；
///   * v2 的行里没有教师，教师要用 `my/course/schedule/detail?ukey=` 单条查。
class TimetableApi {
  static const String base = 'https://task.fafu.edu.cn/api8/api';
  static const String timetablePage = 'https://task.fafu.edu.cn/timetable/';
  static const String casLoginUrl =
      'http://auth.fafu.edu.cn/authserver/login?service=http%3A%2F%2Fehall.fafu.edu.cn%2Flogin';

  /// 网关唯一认的 CAS 会话 Cookie
  static const String gatewayCookie = 'NGXCAS';

  static const String _ua = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// CAS 会话 Cookie（必须）
  final String cookie;

  /// 后台任务里可以自己续，所以不是 final
  String _token;

  TimetableApi({String token = '', this.cookie = ''}) : _token = token;

  String get token => _token;

  Map<String, String> get _headers => {
        'Accept': 'application/json, text/plain, */*',
        'Referer': timetablePage,
        'User-Agent': _ua,
        if (cookie.isNotEmpty) 'Cookie': cookie,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  // ------------------------------------------------------------------ 请求

  Future<http.Response> _send(Uri uri) async {
    try {
      return await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw Exception('请求超时（${uri.path}），请检查网络');
    } on SocketException catch (e) {
      throw Exception('网络不通（${uri.path}）：${e.message}');
    } catch (e) {
      throw Exception('请求失败（${uri.path}）：$e');
    }
  }

  Future<Map<String, dynamic>> _get(String path,
      [Map<String, String>? query]) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    var r = await _send(uri);

    // JWT 只有 1 小时：401 就用 Cookie 续一个再试一次
    if (r.statusCode == 401 && cookie.isNotEmpty) {
      try {
        _token = await fetchTokenWithCookie(cookie);
        r = await _send(uri);
      } catch (_) {
        // 续不上就交给下面的错误提示
      }
    }

    return _parse(r, path);
  }

  Map<String, dynamic> _parse(http.Response r, String path) {
    final body = decodeBody(r);
    if (looksHtml(body)) {
      throw Exception('服务器要求重新登录（HTTP ${r.statusCode}）：'
          '登录会话已失效，请重新登录后再试');
    }
    Object? j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      throw Exception(
          '接口返回的不是 JSON（HTTP ${r.statusCode}，$path）：${snippet(body)}');
    }
    if (j is! Map) {
      throw Exception('接口返回异常（HTTP ${r.statusCode}，$path）：${snippet(body)}');
    }
    final m = j.cast<String, dynamic>();
    if (m['code'] == null && r.statusCode == 401) {
      throw Exception('登录凭据已失效（401）：请重新登录后再试');
    }
    if (m['code'] != 200) {
      throw Exception('${m['msg'] ?? '接口返回异常'}（code=${m['code']}）');
    }
    return m;
  }

  // ------------------------------------------------------------- 凭据交换

  /// 用网关 Cookie 换一个新 JWT（后台任务靠这个续期）
  static Future<String> fetchTokenWithCookie(String cookie) async {
    final r = await http.get(
      Uri.parse('$base/he/token'),
      headers: {
        'Accept': 'application/json, text/plain, */*',
        'Referer': timetablePage,
        'User-Agent': _ua,
        'Cookie': cookie,
      },
    ).timeout(const Duration(seconds: 30));

    final body = decodeBody(r);
    if (looksHtml(body)) {
      throw Exception('换取登录凭据失败：会话已失效（HTTP ${r.statusCode}），请重新登录');
    }
    final t = tokenOf(body);
    if (t == null) {
      throw Exception('换取登录凭据失败（HTTP ${r.statusCode}）：${snippet(body)}');
    }
    return t;
  }

  // ---------------------------------------------------------------- 接口

  /// 当前教学周信息：学年、学期、第几周、开学日期
  Future<WeekInfo> weekInfo() async {
    final j = await _get('/hbiz-teachm-proxy/open/ti/teaching-week-info');
    return WeekInfo.fromJson(j['data'] as Map<String, dynamic>);
  }

  /// 各教学周的起止日期
  ///
  /// 注意：`dateAt` 必须是 `yyyy-MM-dd HH:mm:ss`，只给日期服务端会转换失败返回 400。
  Future<List<TeachingWeek>> weekList(String dateAt) async {
    final j = await _get('/hbiz-teachm-proxy/open/ti/teaching-week/list',
        {'dateAt': dateTimeParam(dateAt)});
    return (j['data'] as List? ?? const [])
        .map((e) => TeachingWeek.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 单条课时的完整信息（只有这里才有教师、周次区间、单双周）
  Future<Map<String, dynamic>> lessonDetail(String ukey) async {
    final j = await _get(
        '/hbiz-teachm-proxy/teachmp/my/course/schedule/detail', {'ukey': ukey});
    return (j['data'] as Map<String, dynamic>?) ?? const {};
  }

  /// 某一天的课程（服务端只认"当天"，dateAt 实际被忽略，仅作兼容保留）
  Future<List<Course>> day(String dateAt) async {
    final j = await _get(
        '/hbiz-teachm-proxy/teachmp/my/course/schedule/day/list',
        {'dateAt': dateTimeParam(dateAt)});
    final list = j['data'] as List? ?? const [];
    final out = <Course>[];
    for (final raw in list) {
      final m = raw as Map<String, dynamic>;
      final c = _courseOf(m, week: (m['weekIndex'] as int?) ?? 1);
      if (c != null) out.add(c);
    }
    return out;
  }

  /// 某一教学周的全部课时（不含教师；用于刷新时比对）
  Future<List<Course>> weekLessons(
      String schoolYear, String semester, int weekIndex) async {
    final lessons = await _scanWeek(schoolYear, semester, weekIndex);
    return [for (final l in lessons) l.toCourse('')];
  }

  /// 抓取整学期
  ///
  /// 做法：逐周扫描（每周 1 个请求，4 周并发）→ 按「课程+星期+节次+教室」
  /// 归组成时段 → 每个时段查一次 detail 拿教师 → 把连续周次压缩成区间
  /// （第 2-17 周 / 第 3-7 周|单周），与界面的按周显示完全对得上。
  Future<List<Course>> fetchSemester({
    WeekInfo? info,
    void Function(int done, int total)? onProgress,
  }) async {
    final wi = info ?? await weekInfo();
    final weeks = await weekList(_fmt(DateTime.now()));
    final valid =
        weeks.where((w) => w.weekIndex >= 1).toList(growable: false);
    final total = valid.length;
    var done = 0;

    final groups = <String, List<_Lesson>>{};
    for (var i = 0; i < valid.length; i += 4) {
      final batch = valid.skip(i).take(4).toList();
      final res = await Future.wait(batch.map((w) async {
        try {
          return await _scanWeek(wi.schoolYear, wi.semester, w.weekIndex);
        } catch (_) {
          return <_Lesson>[]; // 单周失败不影响整体
        }
      }));
      for (final list in res) {
        for (final l in list) {
          groups.putIfAbsent(l.slotKey, () => <_Lesson>[]).add(l);
        }
      }
      done += batch.length;
      onProgress?.call(done, total);
    }
    if (groups.isEmpty) return const [];

    // 教师：每个时段查一次（slot 数量通常只有十几个）
    final keys = groups.keys.toList();
    final teachers = <String, String>{};
    for (var i = 0; i < keys.length; i += 5) {
      final batch = keys.skip(i).take(5).toList();
      final res = await Future.wait(batch.map((k) async {
        try {
          final d = await lessonDetail(groups[k]!.first.ukey);
          return cleanTeacher((d['teacherName'] ?? '').toString());
        } catch (_) {
          return '';
        }
      }));
      for (var j = 0; j < batch.length; j++) {
        teachers[batch[j]] = res[j];
      }
    }

    final out = <Course>[];
    for (final k in keys) {
      final list = groups[k]!;
      final ws = list.map((e) => e.week).toSet().toList()..sort();
      final p = _pattern(ws);
      if (p.compact) {
        out.add(list.first.toCourse(teachers[k] ?? '',
            weeksRaw: p.label,
            weekType: p.type,
            startWeek: p.start,
            endWeek: p.end));
      } else {
        // 周次不连续的少数课程：按周拆开，保证哪天有课显示哪天
        for (final w in ws) {
          out.add(list.firstWhere((e) => e.week == w).toCourse(teachers[k] ?? ''));
        }
      }
    }
    out.sort((a, b) {
      final wa = a.startWeek ?? 0, wb = b.startWeek ?? 0;
      if (wa != wb) return wa.compareTo(wb);
      if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
      return (a.periods.isEmpty ? 0 : a.periods.first)
          .compareTo(b.periods.isEmpty ? 0 : b.periods.first);
    });
    return out;
  }

  /// 扫描某一教学周，取出所有真实课时（丢掉花名册行）
  Future<List<_Lesson>> _scanWeek(
      String schoolYear, String semester, int weekIndex) async {
    final j = await _get(
        '/hbiz-teachm-proxy/teachmp/my/course/schedule/v2/week/list',
        {
          'schoolYear': schoolYear,
          'semester': semester,
          'weekIndex': '$weekIndex',
        });
    final days = j['data'] as List? ?? const [];
    final out = <_Lesson>[];
    for (final raw in days) {
      final d = raw as Map<String, dynamic>;
      final wd = d['weekday'] as int?;
      if (wd == null) continue;
      final cs = d['courseSchedules'] as List? ?? const [];
      for (final r in cs) {
        final m = r as Map<String, dynamic>;
        final name = (m['courseName'] ?? '').toString().trim();
        final s = m['startLesson'] as int?;
        if (name.isEmpty || s == null) continue; // 花名册行（无节次）
        final e = (m['endLesson'] as int?) ?? s;
        out.add(_Lesson(
          weekIndex,
          wd,
          s,
          e,
          name,
          (m['classroomName'] ?? '').toString(),
          (m['ukey'] ?? '').toString(),
        ));
      }
    }
    return out;
  }

  static Course? _courseOf(Map<String, dynamic> m, {required int week}) {
    final name = (m['courseName'] ?? '').toString().trim();
    final weekday = m['weekday'] as int?;
    final start = m['startLesson'] as int?;
    if (name.isEmpty || weekday == null || start == null) return null;
    return Course(
      name: name,
      teacher: cleanTeacher((m['teacherName'] ?? '').toString()),
      place: (m['classroomName'] ?? '').toString(),
      weekday: weekday,
      periods: List.generate(
          ((m['endLesson'] as int?) ?? start) - start + 1, (i) => start + i),
      weeksRaw: '第$week周',
      weekType: '每周',
      startWeek: week,
      endWeek: week,
    );
  }

  /// 周次压缩：连续 → 每周；等差 2 → 单/双周；否则不压缩
  static _Pattern _pattern(List<int> ws) {
    if (ws.isEmpty) return const _Pattern(false, '', '每周', null, null);
    final min = ws.first, max = ws.last;
    final span = max - min + 1;
    final label = min == max ? '第$min周' : '第$min-$max周';
    if (span == ws.length) {
      return _Pattern(true, label, '每周', min, max);
    }
    if (span == ws.length * 2 - 1 && ws.every((w) => (w - min) % 2 == 0)) {
      final type = min.isOdd ? '单周' : '双周';
      return _Pattern(true, '$label|$type', type, min, max);
    }
    return const _Pattern(false, '', '每周', null, null);
  }

  // ---------------------------------------------------------------- 工具

  /// 服务端要求 `yyyy-MM-dd HH:mm:ss`
  static String dateTimeParam(String dateAt) =>
      dateAt.length <= 10 ? '$dateAt 00:00:00' : dateAt;

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String decodeBody(http.Response r) {
    List<int> bytes = r.bodyBytes;
    final enc = (r.headers['content-encoding'] ?? '').toLowerCase();
    if (enc.contains('gzip')) {
      try {
        bytes = gzip.decode(bytes);
      } catch (_) {}
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static bool looksHtml(String body) {
    final t = body.trimLeft().toLowerCase();
    return t.startsWith('<') || t.startsWith('<!doctype');
  }

  /// 教师字段偶尔是「姓名(姓名/拼音)」的重复写法，去掉括号部分
  static String cleanTeacher(String s) {
    final t = s.trim();
    final m = RegExp(r'^([^()（）]+)[（(]([^()（）]*)[)）]$').firstMatch(t);
    if (m == null) return t;
    final a = m.group(1)!.trim(), b = m.group(2)!.trim();
    if (a == b) return a;
    final asciiOnly = RegExp(r'^[A-Za-z0-9 ,.\-]+$').hasMatch(b);
    if (asciiOnly && RegExp(r'[\u4e00-\u9fa5]').hasMatch(a)) return a;
    return t;
  }

  /// 从 JSON（或任意文本）里挖出 access_token
  static String? tokenOf(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['access_token'] != null) {
        return j['access_token'].toString();
      }
    } catch (_) {}
    final m = RegExp(r'"access_token"\s*:\s*"([^"]+)"').firstMatch(body);
    if (m != null) return m.group(1);
    final jwt = RegExp(
            r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*')
        .firstMatch(body);
    return jwt?.group(0);
  }

  /// 读 JWT 载荷里的字段（如 user_name），失败返回空串
  static String jwtField(String token, String field) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return '';
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final j = jsonDecode(payload);
      if (j is Map && j[field] != null) return j[field].toString();
    } catch (_) {}
    return '';
  }

  /// 错误提示里显示一小段返回内容（不可见字符转义，避免"空白报错"）
  static String snippet(String s, [int n = 160]) {
    final t = s.length > n ? '${s.substring(0, n)}…' : s;
    final b = StringBuffer();
    for (final r in t.runes) {
      if (r == 0x0a || r == 0x0d || r == 0x09) {
        b.write(' ');
      } else if (r == 0xfeff) {
        b.write(r'\uFEFF');
      } else if (r < 0x20 || (r > 0x7e && r < 0xa0)) {
        b.write('\\x${r.toRadixString(16).padLeft(2, '0')}');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }
}

/// 一个「课时」：某周某天某几节的一门课（v2 接口的一行）
class _Lesson {
  final int week;
  final int weekday;
  final int start;
  final int end;
  final String name;
  final String place;
  final String ukey;

  const _Lesson(this.week, this.weekday, this.start, this.end, this.name,
      this.place, this.ukey);

  /// 同一门课每周固定时段 → 同一个 slot
  String get slotKey => '$name|$weekday|$start-$end|$place';

  Course toCourse(String teacher,
          {String? weeksRaw,
          String weekType = '每周',
          int? startWeek,
          int? endWeek}) =>
      Course(
        name: name,
        teacher: teacher,
        place: place,
        weekday: weekday,
        periods: [for (var i = start; i <= end; i++) i],
        weeksRaw: weeksRaw ?? '第$week周',
        weekType: weekType,
        startWeek: startWeek ?? week,
        endWeek: endWeek ?? week,
      );
}

/// 周次形态
class _Pattern {
  final bool compact;
  final String label;
  final String type;
  final int? start;
  final int? end;

  const _Pattern(this.compact, this.label, this.type, this.start, this.end);
}

class WeekInfo {
  final String schoolYear;
  final String semester;
  final int weekIndex;
  final String termStartDate;

  WeekInfo(this.schoolYear, this.semester, this.weekIndex, this.termStartDate);

  factory WeekInfo.fromJson(Map<String, dynamic> j) => WeekInfo(
        (j['schoolYear'] ?? '').toString(),
        (j['semester'] ?? '').toString(),
        (j['weekIndex'] as int?) ?? 1,
        (j['termStartDate'] ?? '').toString(),
      );
}

class TeachingWeek {
  final int weekIndex;
  final String startDate;
  final String endDate;

  TeachingWeek(this.weekIndex, this.startDate, this.endDate);

  factory TeachingWeek.fromJson(Map<String, dynamic> j) => TeachingWeek(
        (j['weekIndex'] as int?) ?? 0,
        (j['startDate'] ?? '').toString(),
        (j['endDate'] ?? '').toString(),
      );
}
