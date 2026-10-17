/// 教务系统 .xls 课表解析器（纯 Dart，不依赖 flutter / excel_plus）。
///
/// 输入是把 Excel 工作表读出来的 `List<List<String?>>`（转换在 UI 层完成，
/// 这里保持纯净可单测）。表格结构（真实数据已验证）：
/// - 标题区（第一行附近）：C 列含学期名；
/// - 表头行：含「星期一」…「星期日」，星期列 = C3..C9（0 基索引 2..8）；
/// - 数据行：格内可能拼接多条「课程名/(节次)周次/校区 地点/教师/…」；
/// - 尾部：实践课程行（跳过）与注释行（含 week1Monday / totalWeeks 元信息）。
library;

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/week_mask.dart';

/// 单元格内一条课程记录（解析中间产物，供单测）。
class JwxtCellEntry {
  const JwxtCellEntry({
    required this.name,
    required this.sectionStart,
    required this.sectionEnd,
    required this.weeks,
    required this.location,
    required this.teacher,
  });

  /// 课程名（已 trim，去掉教务导出的前导换行）。
  final String name;

  /// 节次起（格内括号为准）。
  final int sectionStart;

  /// 节次止。
  final int sectionEnd;

  /// 展开后的周次集合（单双周已过滤）。
  final Set<int> weeks;

  /// 地点（「松山湖 松6-604」→「松6-604」，取最后一个空格后）。
  final String location;

  /// 教师。
  final String teacher;
}

/// 教务 Excel 导入结果。
class JwxtImportResult {
  const JwxtImportResult({
    required this.courses,
    required this.skippedCount,
    this.week1Monday,
    this.totalWeeks,
    this.semesterName,
    this.error,
  });

  /// 解析出的课程列表（同格重复已按位合并 weekMask）。
  final List<Course> courses;

  /// 注释行解析出的第一周周一；失败为 null。
  final DateTime? week1Monday;

  /// 注释行解析出的总周数；失败为 null。
  final int? totalWeeks;

  /// 标题区的学期名，如「2026-2027年第1学期」；失败为 null。
  final String? semesterName;

  /// 匹配到但无法生成有效课程的条数（周次空集 / 节次越界）。
  final int skippedCount;

  /// 解析失败原因（如定位不到表头行）；null 表示成功。
  final String? error;

  /// 是否可以进入预览。
  bool get isSuccessful => error == null && courses.isNotEmpty;

  /// 学期三件套是否齐全（可自动填写 meta）。
  bool get hasMeta => week1Monday != null && totalWeeks != null;
}

/// 解析周次文本 → 周次集合（已验证的算法，改前先跑单测）：
/// 1) 含「单」→ 只留奇数周；含「双」→ 只留偶数周；
/// 2) 去掉 单/双/周 及全半角括号；
/// 3) 按 `,，、;；` 与空白切段，每段是「a-b」区间（含 – ~ — 到 至）或单周；
/// 4) 空串 / 乱码 → 空集合，绝不抛异常。
Set<int> parseWeeksText(String text) {
  if (text.trim().isEmpty) {
    return <int>{};
  }
  final bool odd = text.contains('单');
  final bool even = text.contains('双');
  final String cleaned = text
      .replaceAll(RegExp(r'[（(]?\s*[单双]\s*周?\s*[）)]?'), '')
      .replaceAll('周', '');
  final Set<int> weeks = <int>{};
  for (final String segment in cleaned.split(RegExp(r'[,，、;；\s]+'))) {
    if (segment.isEmpty) {
      continue;
    }
    final RegExpMatch? range = RegExp(r'^(\d+)[-–~—到至](\d+)$')
        .firstMatch(segment);
    if (range != null) {
      int a = int.parse(range.group(1)!);
      int b = int.parse(range.group(2)!);
      if (a > b) {
        final int t = a;
        a = b;
        b = t;
      }
      for (int w = a; w <= b; w++) {
        if (w >= minWeek && w <= maxWeek) {
          weeks.add(w);
        }
      }
    } else {
      final int? single = int.tryParse(segment);
      if (single != null && single >= minWeek && single <= maxWeek) {
        weeks.add(single);
      }
    }
  }
  if (odd) {
    return weeks.where((int w) => w % 2 == 1).toSet();
  }
  if (even) {
    return weeks.where((int w) => w % 2 == 0).toSet();
  }
  return weeks;
}

/// 单元格提取正则（真实数据已验证）：
/// group1 课程名 / group2-3 节次起止 / group4 周次 / group5 校区+地点 / group6 教师。
final RegExp _cellPattern = RegExp(
  r'([^/]+)/\((\d+)-(\d+)节\)([^/]+)/([^/]+)/([^/]+)/',
);

/// 解析一个课程格（一格可能拼接多条，逐条提取）。
List<JwxtCellEntry> parseCellText(String cellText) {
  final List<JwxtCellEntry> entries = <JwxtCellEntry>[];
  for (final RegExpMatch match in _cellPattern.allMatches(cellText)) {
    entries.add(
      JwxtCellEntry(
        name: match.group(1)!.trim(),
        sectionStart: int.parse(match.group(2)!),
        sectionEnd: int.parse(match.group(3)!),
        weeks: parseWeeksText(match.group(4)!),
        location: _shortLocation(match.group(5)!),
        teacher: match.group(6)!.trim(),
      ),
    );
  }
  return entries;
}

/// 「松山湖 松6-604」→「松6-604」（取最后一个空格后的部分）。
String _shortLocation(String raw) {
  final String trimmed = raw.trim();
  final int lastSpace = trimmed.lastIndexOf(' ');
  return lastSpace == -1 ? trimmed : trimmed.substring(lastSpace + 1);
}

/// 注释行元信息：「本学期2026-08-31正式上课…共20周.」。
final RegExp _metaPattern = RegExp(
  r'(\d{4}-\d{2}-\d{2})\s*正式上课.*?共\s*(\d+)\s*周',
);

/// 解析整张工作表。
///
/// - 定位含「星期一」的表头行，星期列从表头动态取（结构上即 C3..C9）；
/// - 数据行扫到「注」开头或含「实践课程」的行为止；
/// - 节次上界用 `Period.defaults.length`，不硬编码；
/// - 同格/跨格重复（课名+教师+地点+星期+节次完全相同、周次不同）按位合并
///   weekMask；单双周互补课地点不同 → 不同 key → 仍是独立课程。
JwxtImportResult parseJwxtWorkbook(List<List<String?>> rows) {
  // 1. 定位表头行
  int headerRow = -1;
  for (int r = 0; r < rows.length; r++) {
    if (_rowText(rows[r]).contains('星期一')) {
      headerRow = r;
      break;
    }
  }
  if (headerRow == -1) {
    return const JwxtImportResult(
      courses: <Course>[],
      skippedCount: 0,
      error: '未找到课表表头（教务导出的表格应有「星期一」表头行）',
    );
  }

  // 2. 星期列起始位置（表头行里「星期一」所在列，结构上即 0 基索引 2）
  final List<String?> headerCells = rows[headerRow];
  int weekColStart = -1;
  for (int c = 0; c < headerCells.length; c++) {
    final String? cell = headerCells[c];
    if (cell != null && cell.contains('星期一')) {
      weekColStart = c;
      break;
    }
  }

  // 3. 元信息：注释行（全表扫「正式上课」）+ 学期名（表头行之前含「学期」的格）
  DateTime? week1Monday;
  int? totalWeeks;
  for (final List<String?> row in rows) {
    final String text = _rowText(row);
    final RegExpMatch? match = _metaPattern.firstMatch(text);
    if (match != null) {
      week1Monday = DateTime.tryParse(match.group(1)!);
      totalWeeks = int.tryParse(match.group(2)!);
      if (week1Monday != null && totalWeeks != null) {
        break;
      }
    }
  }
  String? semesterName;
  outer:
  for (int r = 0; r < headerRow; r++) {
    for (final String? cell in rows[r]) {
      if (cell != null && cell.contains('学期')) {
        semesterName = cell.trim();
        break outer;
      }
    }
  }

  // 4. 数据行 → 课程格 → 条目
  final int maxSection = Period.defaults.length;
  int skipped = 0;
  // key 用 record（替代 '|' 拼接字符串），value 累积 weekMask
  final Map<(String, String, String, int, int, int), int> merged =
      <(String, String, String, int, int, int), int>{};
  for (int r = headerRow + 1; r < rows.length; r++) {
    final List<String?> row = rows[r];
    final String rowText = _rowText(row);
    if (rowText.trim().isEmpty) {
      continue;
    }
    // 实践课程行 / 注释行 → 数据区结束
    if (rowText.trim().startsWith('注') || rowText.contains('实践课程')) {
      break;
    }
    for (int dayWeek = 1; dayWeek <= 7; dayWeek++) {
      final int col = weekColStart + dayWeek - 1;
      if (col < 0 || col >= row.length) {
        continue;
      }
      final String? cell = row[col];
      if (cell == null || cell.trim().isEmpty) {
        continue;
      }
      for (final JwxtCellEntry entry in parseCellText(cell)) {
        final bool sectionValid =
            entry.sectionStart >= 1 &&
            entry.sectionEnd >= entry.sectionStart &&
            entry.sectionEnd <= maxSection;
        if (!sectionValid || entry.weeks.isEmpty || entry.name.isEmpty) {
          skipped++;
          continue;
        }
        final (String, String, String, int, int, int) key = (
          entry.name,
          entry.teacher,
          entry.location,
          dayWeek,
          entry.sectionStart,
          entry.sectionEnd,
        );
        merged[key] = (merged[key] ?? 0) | weekMaskFromWeeks(entry.weeks);
      }
    }
  }

  final List<Course> courses = <Course>[];
  int index = 1;
  merged.forEach(((String, String, String, int, int, int) key, int weekMask) {
    final (
      String name,
      String teacher,
      String location,
      int dayWeek,
      int sectionStart,
      int sectionEnd,
    ) = key;
    courses.add(
      Course(
        id: 'jw_${index.toString().padLeft(3, '0')}',
        name: name,
        teacher: teacher,
        location: location,
        colorValue: colorValueFromName(name),
        dayWeek: dayWeek,
        sectionStart: sectionStart,
        sectionEnd: sectionEnd,
        weekMask: weekMask,
        note: '',
      ),
    );
    index++;
  });

  if (courses.isEmpty) {
    return JwxtImportResult(
      courses: const <Course>[],
      skippedCount: skipped,
      week1Monday: week1Monday,
      totalWeeks: totalWeeks,
      semesterName: semesterName,
      error: '未识别到任何课程，请确认选的是教务系统导出的课表',
    );
  }
  return JwxtImportResult(
    courses: courses,
    skippedCount: skipped,
    week1Monday: week1Monday,
    totalWeeks: totalWeeks,
    semesterName: semesterName,
  );
}

/// 整行拼接文本（定位表头/元信息/终止行用）。
String _rowText(List<String?> row) {
  return row
      .where((String? cell) => cell != null && cell.trim().isNotEmpty)
      .join(' ');
}
