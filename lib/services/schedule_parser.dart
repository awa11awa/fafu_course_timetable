import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/course.dart';

/// 解析正方「学生个人课表」页面
///
/// 单元格结构固定为：
///   课程名称 <br> 周X第A,B节{周次} <br> 教师 <br> 地点
/// 同一格内多门课之间用 <br><br> 分隔。
class ScheduleParser {
  static const Map<String, int> _dayIndex = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
  };

  static final RegExp _reTime = RegExp(
      r'周([一二三四五六日天])\s*第(\d+)\s*(?:[,，]\s*(\d+))?\s*节(?:\s*\{\s*([^}]*)\s*\})?');
  static final RegExp _reRange = RegExp(r'第\s*(\d+)\s*[-~]\s*(\d+)\s*周');
  static final RegExp _reSingle = RegExp(r'第\s*(\d+)\s*周');
  static final RegExp _rePeriodLabel = RegExp(r'第\s*(\d+)\s*节');

  /// 返回 (课程列表, 学年, 学期)
  static (List<Course>, String, String) parse(String html) {
    final doc = html_parser.parse(html);
    final year = _selectedOption(doc, 'xnd');
    final term = _selectedOption(doc, 'xqd');

    final table = doc.querySelector('table#Table1') ?? _biggestTable(doc);
    if (table == null) return (<Course>[], year, term);

    final grid = _buildGrid(table);
    if (grid.isEmpty) return (<Course>[], year, term);

    // 表头：列号 -> 星期
    final dayOfCol = <int, int>{};
    for (var c = 0; c < grid[0].length; c++) {
      final td = grid[0][c];
      if (td == null) continue;
      final text = _text(td);
      for (var d = 1; d <= 7; d++) {
        if (text.contains(Course.weekdayNames[d - 1])) dayOfCol[c] = d;
      }
    }

    // 节次列：紧跟在合并的「时间」列之后
    var periodCol = 1;
    for (var c = 0; c < grid[0].length; c++) {
      final td = grid[0][c];
      if (td != null && _text(td).contains('时间')) {
        periodCol = c + (_intAttr(td, 'colspan') ?? 1) - 1;
        break;
      }
    }

    final courses = <Course>[];
    final seen = <dom.Element>{};

    for (var r = 1; r < grid.length; r++) {
      for (var c = 0; c < grid[r].length; c++) {
        final td = grid[r][c];
        if (td == null || seen.contains(td)) continue;
        if (!dayOfCol.containsKey(c)) continue;

        final blocks = _cellBlocks(td);
        if (blocks.isEmpty) continue;
        seen.add(td);

        // 网格兜底：单元格跨 rowspan 时按起始节次推算
        var periods = <int>[];
        if (periodCol < grid[r].length) {
          final pt = grid[r][periodCol];
          final pm = pt == null ? null : _rePeriodLabel.firstMatch(_text(pt));
          if (pm != null) {
            final start = int.parse(pm.group(1)!);
            final span = _intAttr(td, 'rowspan') ?? 1;
            periods = List.generate(span, (i) => start + i);
          }
        }

        for (final lines in blocks) {
          final course = _parseBlock(lines, dayOfCol[c]!, periods);
          if (course != null) courses.add(course);
        }
      }
    }
    return (courses, year, term);
  }

  static Course? _parseBlock(List<String> lines, int gridDay, List<int> gridPeriods) {
    final name = lines.first;
    if (name.isEmpty) return null;
    if (Course.weekdayNames.contains(name)) return null;
    if (const ['时间', '上午', '下午', '晚上', '早晨'].contains(name)) return null;
    if (name.startsWith('第') && name.endsWith('节')) return null;

    final rest = lines.sublist(1);
    var timeIdx = -1;
    for (var i = 0; i < rest.length; i++) {
      if (rest[i].contains('节') || rest[i].startsWith('{')) {
        timeIdx = i;
        break;
      }
    }
    final String timeRaw;
    final List<String> after;
    if (timeIdx < 0) {
      timeRaw = '';
      after = rest;
    } else {
      timeRaw = rest[timeIdx];
      after = rest.sublist(timeIdx + 1);
    }
    final teacher = after.isNotEmpty ? after[0] : '';
    final place = after.length > 1 ? after[1] : '';

    var day = gridDay;
    var periods = List<int>.from(gridPeriods);
    var weeks = '';

    final m = _reTime.firstMatch(timeRaw) ?? _reTime.firstMatch(name);
    if (m != null) {
      day = _dayIndex[m.group(1)!] ?? gridDay;
      final p1 = int.parse(m.group(2)!);
      final p2 = m.group(3) != null ? int.parse(m.group(3)!) : p1;
      periods = List.generate(p2 - p1 + 1, (i) => p1 + i);
      weeks = m.group(4) ?? '';
    } else {
      final w = RegExp(r'\{([^}]*)\}').firstMatch(timeRaw);
      if (w != null) weeks = w.group(1)!;
    }

    var weekType = '每周';
    if (weeks.contains('单')) {
      weekType = '单周';
    } else if (weeks.contains('双')) {
      weekType = '双周';
    }
    int? startWeek, endWeek;
    final rng = _reRange.firstMatch(weeks);
    if (rng != null) {
      startWeek = int.parse(rng.group(1)!);
      endWeek = int.parse(rng.group(2)!);
    } else {
      final one = _reSingle.firstMatch(weeks);
      if (one != null) {
        startWeek = endWeek = int.parse(one.group(1)!);
      }
    }

    return Course(
      name: name,
      teacher: teacher,
      place: place,
      weekday: day,
      periods: periods,
      weeksRaw: weeks,
      weekType: weekType,
      startWeek: startWeek,
      endWeek: endWeek,
    );
  }

  /// 把带 rowspan/colspan 的表格还原成二维网格
  static List<List<dom.Element?>> _buildGrid(dom.Element table) {
    // 坑：package:html 按 HTML5 规范解析，会给 <table> **自动补上 <tbody>**，
    // 所以 `table.children` 拿到的是 [tbody] 而不是 [tr, tr, ...]。
    // 必须用后代查询取 <tr>，并排除嵌套表格里的行。
    final rows = table
        .querySelectorAll('tr')
        .where((tr) => identical(_nearestTable(tr), table))
        .toList();

    final occupied = <String, dom.Element>{};
    for (var r = 0; r < rows.length; r++) {
      var col = 0;
      final cells = rows[r]
          .children
          .where((e) => e.localName == 'td' || e.localName == 'th')
          .toList();
      for (final td in cells) {
        while (occupied.containsKey('$r,$col')) {
          col++;
        }
        final rowspan = _intAttr(td, 'rowspan') ?? 1;
        final colspan = _intAttr(td, 'colspan') ?? 1;
        for (var dr = 0; dr < rowspan; dr++) {
          for (var dc = 0; dc < colspan; dc++) {
            occupied['${r + dr},${col + dc}'] = td;
          }
        }
        col += colspan;
      }
    }
    if (occupied.isEmpty) return [];
    var maxR = 0, maxC = 0;
    for (final k in occupied.keys) {
      final parts = k.split(',');
      final r = int.parse(parts[0]), c = int.parse(parts[1]);
      if (r > maxR) maxR = r;
      if (c > maxC) maxC = c;
    }
    return List.generate(
        maxR + 1, (r) => List.generate(maxC + 1, (c) => occupied['$r,$c']));
  }

  /// 单元格 -> 若干门课，每门课是若干行文本
  static List<List<String>> _cellBlocks(dom.Element td) {
    var raw = td.innerHtml;
    raw = raw.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    raw = raw.replaceAll(
        RegExp(r'</(p|div|tr)>', caseSensitive: false), '\n');
    final text = html_parser.parse(raw).documentElement?.text ?? '';
    final blocks = <List<String>>[];
    for (final chunk in text.split(RegExp(r'\n\s*\n+'))) {
      final lines = chunk
          .split('\n')
          .map((e) => e.replaceAll('\u00a0', ' ').trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.replaceAll(RegExp(r'\s+'), ' '))
          .toList();
      if (lines.isNotEmpty) blocks.add(lines);
    }
    return blocks;
  }

  static String _text(dom.Element e) =>
      e.text.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  static int? _intAttr(dom.Element e, String name) =>
      int.tryParse(e.attributes[name] ?? '');

  /// 向上找最近的 <table> 祖先；用于排除嵌套表格里的 <tr>
  static dom.Element? _nearestTable(dom.Element node) {
    dom.Node? p = node.parent;
    while (p != null) {
      if (p is dom.Element && p.localName == 'table') return p;
      p = p.parent;
    }
    return null;
  }

  static String _selectedOption(dom.Document doc, String name) {
    final sel = doc.querySelector('select[name="$name"]');
    if (sel == null) return '';
    final opt = sel.querySelector('option[selected]') ?? sel.querySelector('option');
    return opt?.attributes['value'] ?? opt?.text.trim() ?? '';
  }

  static dom.Element? _biggestTable(dom.Document doc) {
    dom.Element? best;
    var bestCount = 0;
    for (final t in doc.querySelectorAll('table')) {
      final n = t.querySelectorAll('td').length;
      if (n > bestCount) {
        bestCount = n;
        best = t;
      }
    }
    return best;
  }
}
