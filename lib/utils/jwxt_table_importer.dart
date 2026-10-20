/// 教务系统「逐条课程明细表」解析器（纯 Dart，不依赖 flutter / excel_plus）。
///
/// 新版正方导出的 xlsx 通常有三张工作表：「课表」（周课表网格，走
/// [parseJwxtWorkbook]）、「课程明细」（一行一条课程记录，本文件）、
/// 「说明」。本解析器处理第二种，表头形如：
///
/// ```
/// 序号 | 星期 | 节次 | 上课时间 | 课程名称 | 周次 | 校区 | 场地 | 教师 | 课程性质 | 总学时 | 学分
/// ```
///
/// - 列按**表头文字**定位（含「课程名称」→ 课名列……），不写死列号；
/// - 合并 key = (课名, 教师, 星期, 节次起止, 地点)，周次取并集；
///   **不跨教师合并**——军理课每周换老师是真实排课，跨教师合并会丢信息；
/// - week1Monday / totalWeeks / periods 明细表里没有 → 返回 null（不猜）。
library;

import 'package:timetable/models/course.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/generic_cell_parser.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/week_mask.dart';

/// 识别并解析「逐条课程表」（表头含 课程名称 + 星期 等列）。
///
/// 不是这种表（前 5 行找不到「课程名 × 星期」表头，或缺必需列）
/// → 返回 null，让调用方继续试网格解析。
JwxtImportResult? parseJwxtDetailTable(List<List<String?>> rows) {
  // 1. 前 5 行找表头行：同时含「课程名」与「星期/周几」表头格
  int headerRow = -1;
  for (int r = 0; r < rows.length && r < 5; r++) {
    if (_hasCellContaining(rows[r], '课程名') &&
        (_hasCellContaining(rows[r], '星期') ||
            _hasCellContaining(rows[r], '周几'))) {
      headerRow = r;
      break;
    }
  }
  if (headerRow == -1) {
    return null;
  }

  // 2. 列定位（按表头文字；「课程名称」含「课程名」，一个关键词即可）
  final List<String?> header = rows[headerRow];
  final int? nameCol = _columnOf(header, '课程名');
  final int? dayCol = _columnOf(header, '星期') ?? _columnOf(header, '周几');
  final int? sectionCol = _columnOf(header, '节次');
  final int? weeksCol = _columnOf(header, '周次');
  if (nameCol == null ||
      dayCol == null ||
      sectionCol == null ||
      weeksCol == null) {
    return null;
  }
  final int? locationCol =
      _columnOf(header, '场地') ??
      _columnOf(header, '地点') ??
      _columnOf(header, '教室');
  final int? teacherCol = _columnOf(header, '教师') ?? _columnOf(header, '老师');

  // 3. 学期名：表头行之前的标题行里找（找不到 → null）
  String? semesterName;
  outer:
  for (int r = 0; r < headerRow; r++) {
    for (final String? cell in rows[r]) {
      if (cell != null && cell.contains('学期')) {
        semesterName = extractSemesterName(cell);
        break outer;
      }
    }
  }

  // 4. 逐行解析 → 按 key 合并（周次取并集）
  int skipped = 0;
  final Map<(String, String, int, int, int, String), int> merged =
      <(String, String, int, int, int, String), int>{};
  for (int r = headerRow + 1; r < rows.length; r++) {
    final List<String?> row = rows[r];
    String? at(int? col) => col == null || col >= row.length ? null : row[col];
    final String name = (at(nameCol) ?? '').trim();
    if (name.isEmpty) {
      continue;
    }
    final int? dayWeek = _matchDayValue(at(dayCol));
    final (int, int)? section = _matchSectionValue(at(sectionCol));
    final Set<int> weeks = parseWeeksText(at(weeksCol) ?? '');
    if (dayWeek == null || section == null || weeks.isEmpty) {
      // 有课名但星期/节次无效或周次空集 → 跳过并计数
      skipped++;
      continue;
    }
    // 地点 = 场地列原文（校区不拼接、直接丢弃，保持简洁）
    final String location = (at(locationCol) ?? '').trim();
    final String teacher = (at(teacherCol) ?? '').trim();
    final (String, String, int, int, int, String) key = (
      name,
      teacher,
      dayWeek,
      section.$1,
      section.$2,
      location,
    );
    merged[key] = (merged[key] ?? 0) | weekMaskFromWeeks(weeks);
  }

  // 5. 生成课程（id 与网格解析同规则，jw_ 前缀）
  final List<Course> courses = <Course>[];
  int index = 1;
  merged.forEach(((String, String, int, int, int, String) key, int weekMask) {
    final (
      String name,
      String teacher,
      int dayWeek,
      int start,
      int end,
      String location,
    ) = key;
    courses.add(
      Course(
        id: 'jw_${index.toString().padLeft(3, '0')}',
        name: name,
        teacher: teacher,
        location: location,
        colorValue: colorValueFromName(name),
        dayWeek: dayWeek,
        sectionStart: start,
        sectionEnd: end,
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
      error: '课程明细表里没有可识别的课程记录',
    );
  }
  return JwxtImportResult(
    courses: courses,
    skippedCount: skipped,
    semesterName: semesterName,
  );
}

// ───────────────────── 私有辅助 ─────────────────────

/// 行里是否有含关键词的表头格。
bool _hasCellContaining(List<String?> row, String keyword) {
  for (final String? cell in row) {
    if (cell != null && cell.contains(keyword)) {
      return true;
    }
  }
  return false;
}

/// 表头行里第一个含关键词的列号；找不到返回 null。
int? _columnOf(List<String?> header, String keyword) {
  for (int c = 0; c < header.length; c++) {
    final String? cell = header[c];
    if (cell != null && cell.trim().contains(keyword)) {
      return c;
    }
  }
  return null;
}

/// 星期列取值：「星期一」..「星期日」/「周一」..「周日」/ 纯数字 1..7。
int? _matchDayValue(String? cell) {
  if (cell == null) {
    return null;
  }
  final String trimmed = cell.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final RegExpMatch? full = RegExp(r'^(?:星期|周|礼拜)([一二三四五六日天1-7])$')
      .firstMatch(trimmed);
  if (full != null) {
    return dayChars[full.group(1)!];
  }
  // 逐条表的星期列语义明确，裸数字 1..7 也认（网格表表头不认裸数字，
  // 那是为了避免把数据行编号当表头；这里列语义已确定，无此风险）
  final int? number = int.tryParse(trimmed);
  if (number != null && number >= 1 && number <= 7) {
    return number;
  }
  return null;
}

/// 节次列取值：「3-5」/「3」/「3-5节」→ (起, 止)；脏数据返回 null。
(int, int)? _matchSectionValue(String? cell) {
  if (cell == null) {
    return null;
  }
  final RegExpMatch? match = RegExp(r'^(\d+)(?:\s*[-–~]\s*(\d+))?\s*节?$')
      .firstMatch(cell.trim());
  if (match == null) {
    return null;
  }
  final int start = int.parse(match.group(1)!);
  final int end = match.group(2) == null ? start : int.parse(match.group(2)!);
  if (start < 1 || end < start || end > absMaxSection) {
    return null;
  }
  return (start, end);
}
