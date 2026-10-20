/// 教务系统 .xls 课表解析器（纯 Dart，不依赖 flutter / excel_plus）。
///
/// 输入是把 Excel 工作表读出来的 `List<List<String?>>`（转换在 UI 层完成，
/// 这里保持纯净可单测）。表格结构（真实数据已验证）：
/// - 标题区（第一行附近）：含学期名；
/// - 表头行：星期表头（两级识别，见 [_matchDayHeader]）；
/// - 数据行：左侧节次列 + 星期课程格。课程格三层解析：第 1 层正方
///   `/` 紧凑格式（[parseCellText]），未命中才走第 2/3 层通用解析
///   （[parseGenericCell]，见 generic_cell_parser.dart）；
/// - 尾部：实践课程行（跳过）与注释行（含 week1Monday / totalWeeks 元信息）。
library;

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/generic_cell_parser.dart';
import 'package:timetable/utils/week_mask.dart';

// parseWeeksText 已原样迁移到 generic_cell_parser（单一实现），
// 这里 re-export 保持既有 import 路径兼容（A 组测试无需改动）。
export 'package:timetable/utils/generic_cell_parser.dart' show parseWeeksText;

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
    this.periods,
    this.usedDefaultPeriods = true,
    this.detectedSectionCount = 0,
    this.fallbackCount = 0,
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

  /// 节次列构造出的作息（E2 三态，**绝不缩水**）：
  /// - 读到 ≥ 1 个有效时间 → 构造的 periods；
  /// - 只有编号没时间 / 连编号都没有 → null。
  /// null 时调用方保留现有 periods，不补 `--:--` 假时间。
  final List<Period>? periods;

  /// true = periods 为 null，调用方沿用现有/默认作息。
  final bool usedDefaultPeriods;

  /// 行标签推断出的节次数（如广科汉字节次表「一..五」= 5）。
  final int detectedSectionCount;

  /// 走第 3 层兜底的条目数（预览页「导入后可手动补全」警示用）。
  final int fallbackCount;

  /// 匹配到但无法生成有效课程的条数（周次空集 / 节次越界）。
  final int skippedCount;

  /// 解析失败原因（如定位不到表头行）；null 表示成功。
  final String? error;

  /// 是否可以进入预览。
  bool get isSuccessful => error == null && courses.isNotEmpty;

  /// 学期三件套是否齐全（可自动填写 meta）。
  bool get hasMeta => week1Monday != null && totalWeeks != null;
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

// ───────────────────── 三行式条目（新版正方） ─────────────────────

/// 三行式条目第 2 行：`1-3节  6-17周` / `1-2节  第16周`
/// （节次 起-止 + 其后是周次）。
final RegExp _threeLineSecondPattern = RegExp(
  r'^(\d+)\s*[-–~]\s*(\d+)\s*节\s*(.+)$',
);

/// 解析三行式条目（新版正方「课表」工作表的课程格）：
///
/// ```
/// 行1: 课名
/// 行2: `<节次起>-<节次止>节  <周次>`   例：`1-3节  6-17周`
/// 行3: `<地点>  <教师>`               地点与教师间是 ≥ 2 个空格
/// ```
///
/// 恰好 3 行、第 2 行匹配节次+周次、周次能解析出非空集合才算命中
/// （两条信息都齐）；未命中返回 null，由 [_parseCellLayers] 回落到
/// 既有三层解析。广科单换行格式切出来只有 1 个条目且非 3 行 →
/// 天然不命中，零回归。
JwxtCellEntry? _parseThreeLineChunk(String chunk) {
  final List<String> lines = chunk
      .split(RegExp(r'\r\n|\r|\n'))
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
  if (lines.length != 3) {
    return null;
  }
  final String name = lines[0];
  if (name.isEmpty) {
    return null;
  }
  final RegExpMatch? match = _threeLineSecondPattern.firstMatch(lines[1]);
  if (match == null) {
    return null;
  }
  final Set<int> weeks = parseWeeksText(match.group(3)!.trim());
  if (weeks.isEmpty) {
    return null;
  }
  // 行 3 按 ≥ 2 个空格切 [地点, 教师]（1 段 = 无教师；≥ 3 段 = 第一段
  // 地点、其余归教师，容忍地点本身含 2 空格的极端写法）
  final List<String> parts = lines[2]
      .split(RegExp(r'[ \t]{2,}'))
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return null;
  }
  return JwxtCellEntry(
    name: name,
    sectionStart: int.parse(match.group(1)!),
    sectionEnd: int.parse(match.group(2)!),
    weeks: weeks,
    location: parts.first,
    teacher: parts.length >= 2 ? parts.sublist(1).join(' ') : '',
  );
}

/// 课程格分层解析（整格 → 按空行切条目 → 每条目独立走层）：
///
/// 0. **三行式**（[_parseThreeLineChunk]，新版正方，多课格用空行分隔）；
/// 1. 正方 `/` 紧凑格式（[parseCellText]，命中 ≥ 1 条 → 该条目不进第 2 层）；
/// 2. 通用启发式（[parseGenericCell]，solid 优先）；
/// 3. 兜底（fallback 条目，条数由返回值第二项带回）。
///
/// 空行切条目只影响新版正方；广科/青果格式无空行 → 整格一个条目，
/// 各层行为与旧版完全一致。
(List<_RawEntry>, int) _parseCellLayers(String cell) {
  final List<_RawEntry> entries = <_RawEntry>[];
  int fallbackAdded = 0;
  // 按**空行**切条目。
  //
  // ⚠️ 不能写成 `(?:\r\n|\r|\n)[ \t]*(?:\r\n|\r|\n)`：
  // 那个正则会在单个 `\r\n` 上回溯 —— 先试 `\r\n` 失败，
  // 退回只匹配 `\r`，再用 `\n` 当第二个换行 —— 结果每个换行都被
  // 当成空行，格子被切成一行一个 chunk，三行式解析永远拿不到 3 行（真机实测过）。
  // 用 `\r?\n` 作为单位，单个换行行就不可能凑出两个。
  final List<String> chunks = cell.split(RegExp(r'\r?\n[ \t]*\r?\n'));
  for (final String chunk in chunks) {
    final String trimmed = chunk.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    // 第 0 层：三行式条目
    final JwxtCellEntry? threeLine = _parseThreeLineChunk(trimmed);
    if (threeLine != null) {
      entries.add(_RawEntry.fromFirstLayer(threeLine));
      continue;
    }
    // 第 1 层：正方 `/` 紧凑格式
    final List<JwxtCellEntry> firstLayer = parseCellText(trimmed);
    if (firstLayer.isNotEmpty) {
      entries.addAll(<_RawEntry>[
        for (final JwxtCellEntry e in firstLayer) _RawEntry.fromFirstLayer(e),
      ]);
      continue;
    }
    // 第 2/3 层：通用启发式 + 兜底
    final List<GenericCellEntry> generic = parseGenericCell(trimmed);
    final List<GenericCellEntry> solid = <GenericCellEntry>[
      for (final GenericCellEntry e in generic)
        if (!e.fallback) e,
    ];
    if (solid.isNotEmpty) {
      entries.addAll(<_RawEntry>[
        for (final GenericCellEntry e in solid) _RawEntry.fromGeneric(e),
      ]);
    } else if (generic.isNotEmpty) {
      // 第 3 层兜底：宁可粗糙也要出东西，绝不静默丢弃
      fallbackAdded += generic.length;
      entries.addAll(<_RawEntry>[
        for (final GenericCellEntry e in generic) _RawEntry.fromGeneric(e),
      ]);
    }
  }
  return (entries, fallbackAdded);
}

/// 注释行元信息：「本学期2026-08-31正式上课…共20周.」。
final RegExp _metaPattern = RegExp(
  r'(\d{4}-\d{2}-\d{2})\s*正式上课.*?共\s*(\d+)\s*周',
);

/// 节次绝对上界：只用于防脏数据（如「99 节」）。
///
/// **不与 detectedSectionCount / Period.defaults.length 挂钩**（E1 教训：
/// 广科样表节次列是汉字「一..五」，行推断只能数出 5，若拿它当上界校验
/// 格内自带的 (9-10节)，会误杀约 10 门晚课）。行推断节数只是「标签数」，
/// 不代表表格真实节次容量——格内自带节次一律以绝对界校验。
///
/// 公开供 jwxt_table_importer（逐条表解析）复用。
const int absMaxSection = 24;

// ───────────────────── 表头两级识别 ─────────────────────

/// 汉字/数字 → 星期号（1..7）；「日」「天」都是 7。
///
/// 公开供 jwxt_table_importer（逐条表解析）复用。
const Map<String, int> dayChars = <String, int>{
  '一': 1,
  '二': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '日': 7,
  '天': 7,
  '1': 1,
  '2': 2,
  '3': 3,
  '4': 4,
  '5': 5,
  '6': 6,
  '7': 7,
};

/// 第一级完整形式：`(星期|周|礼拜)(一..日/天|1..7)`，格级完全匹配。
final RegExp _dayHeaderFullPattern = RegExp(r'^(?:星期|周|礼拜)([一二三四五六日天1-7])$');

/// 第二级裸字：单个 一/二/…/六/日/天（**不认裸数字**，避免把
/// 数据行里的编号格当表头）。
final RegExp _dayHeaderBarePattern = RegExp(r'^([一二三四五六日天])$');

/// 表头格 → 星期号（1..7）；不匹配返回 null。
///
/// - [bare] = false：第一级完整形式（`星期一`/`周二`/`礼拜三`/`星期3`）；
/// - [bare] = true：第二级裸字（`一`）。仅当第一级在全表命中 < 3 个格时
///   才由调用方启用。
int? _matchDayHeader(String? cell, {required bool bare}) {
  if (cell == null) {
    return null;
  }
  final String trimmed = cell.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final RegExpMatch? match =
      (bare ? _dayHeaderBarePattern : _dayHeaderFullPattern).firstMatch(
        trimmed,
      );
  if (match == null) {
    return null;
  }
  return dayChars[match.group(1)!];
}

/// 数一行里命中星期表头的格数。
int _countDayCells(List<String?> row, {required bool bare}) {
  int count = 0;
  for (final String? cell in row) {
    if (_matchDayHeader(cell, bare: bare) != null) {
      count++;
    }
  }
  return count;
}

// ───────────────────── 节次行标签 ─────────────────────

/// 节次列一格的识别产物：编号 + 可选时间。
class _SectionLabel {
  const _SectionLabel(this.number, this.time);

  /// 读到的节次编号；null = 该格只有时间（编号由行序推断）。
  final int? number;

  /// (start, end)，格式 `HH:MM`；null = 没读到时间。
  final (String, String)? time;
}

/// 识别节次列格文本，覆盖五种形态：
/// 1. `^\d{1,2}$`（纯编号）；
/// 2. `第N节`；
/// 3. `N\nHH:MM-HH:MM`（编号 + 时间，多行格）；
/// 4. `HH:MM-HH:MM`（纯时间，编号靠行序）；
/// 5. `N\nHH:MM\nHH:MM`（编号 + 开始/结束两个独立时间点，
///    新版正方三段式，如 `1\n08:00\n08:40`）。
///
/// 都不是（如汉字「一」「二」、文字「上午」）→ null。
_SectionLabel? _matchSectionLabel(String text) {
  final List<String> lines = text
      .split(RegExp(r'\r\n|\r|\n'))
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
  int? number;
  (String, String)? time;
  for (final String line in lines) {
    if (number == null) {
      final RegExpMatch? numbered =
          RegExp(r'^(\d{1,2})$').firstMatch(line) ??
          RegExp(r'^第\s*(\d{1,2})\s*节$').firstMatch(line);
      if (numbered != null) {
        number = int.parse(numbered.group(1)!);
        continue;
      }
    }
    if (time == null) {
      final (String, String)? range = _matchTimeRange(line);
      if (range != null) {
        time = range;
      }
    }
  }
  // 形态 5（新版正方三段式）：编号 + 开始/结束两个独立时间点。
  // 放在形态 1-4 的循环之后：循环通常已抓到编号但抓不到时间
  // （`08:00` 不是 `HH:MM-HH:MM` 范围），由此兜住并补全时间。
  if (time == null && lines.length == 3) {
    final RegExpMatch? numbered = RegExp(r'^(\d{1,2})$').firstMatch(lines[0]);
    final String? start = _matchTimePoint(lines[1]);
    final String? end = _matchTimePoint(lines[2]);
    if (numbered != null && start != null && end != null) {
      return _SectionLabel(int.parse(numbered.group(1)!), (start, end));
    }
  }
  if (number == null && time == null) {
    return null;
  }
  return _SectionLabel(number, time);
}

/// `HH:MM-HH:MM`（兼容 `–`/`~` 与空格），归一化为补零的 `HH:MM`；
/// 非法时间（小时 > 23 / 分钟 > 59）视为没读到。
(String, String)? _matchTimeRange(String line) {
  final RegExpMatch? match = RegExp(
    r'^(\d{1,2}):(\d{2})\s*[-–~]\s*(\d{1,2}):(\d{2})$',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  final int h1 = int.parse(match.group(1)!);
  final int m1 = int.parse(match.group(2)!);
  final int h2 = int.parse(match.group(3)!);
  final int m2 = int.parse(match.group(4)!);
  if (h1 > 23 || h2 > 23 || m1 > 59 || m2 > 59) {
    return null;
  }
  return (
    '${h1.toString().padLeft(2, '0')}:${m1.toString().padLeft(2, '0')}',
    '${h2.toString().padLeft(2, '0')}:${m2.toString().padLeft(2, '0')}',
  );
}

/// 单个时间点 `HH:MM`，归一化为补零；非法时间（小时 > 23 / 分钟 > 59）
/// 视为没读到。三段式节次列（`1\n08:00\n08:40`）的第二/三行用它。
String? _matchTimePoint(String line) {
  final RegExpMatch? match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(line);
  if (match == null) {
    return null;
  }
  final int h = int.parse(match.group(1)!);
  final int m = int.parse(match.group(2)!);
  if (h > 23 || m > 59) {
    return null;
  }
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

// ───────────────────── 三层条目统一 ─────────────────────

/// 三层条目的统一中间结构（校验 + 聚合用）。
class _RawEntry {
  const _RawEntry({
    required this.name,
    required this.sectionStart,
    required this.sectionEnd,
    required this.weeks,
    required this.location,
    required this.teacher,
    required this.fromGeneric,
  });

  factory _RawEntry.fromFirstLayer(JwxtCellEntry entry) => _RawEntry(
    name: entry.name,
    sectionStart: entry.sectionStart,
    sectionEnd: entry.sectionEnd,
    weeks: entry.weeks,
    location: entry.location,
    teacher: entry.teacher,
    fromGeneric: false,
  );

  factory _RawEntry.fromGeneric(GenericCellEntry entry) => _RawEntry(
    name: entry.name,
    sectionStart: entry.sectionStart,
    sectionEnd: entry.sectionEnd,
    weeks: entry.weeks,
    location: entry.location,
    teacher: entry.teacher,
    fromGeneric: true,
  );

  final String name;

  /// 节次起；null = 格内没识别到，由行标签推断。
  final int? sectionStart;

  /// 节次止；null 同上。
  final int? sectionEnd;

  final Set<int> weeks;

  final String location;

  final String teacher;

  /// 第 2/3 层来源：周次空集语义是「没识别到 → 填全部周」。
  /// （第 1 层空集 = 乱码周次 → 跳过，保留原语义。）
  final bool fromGeneric;
}

// ───────────────────── 主流程 ─────────────────────

/// 解析整张工作表。
///
/// - **表头两级识别**：第一级 `(星期|周|礼拜)(一..日|1..7)` 完全匹配；
///   仅当第一级在全表命中 < 3 个格时启用第二级裸字（不认裸数字）。
///   表头行 = 第一个「≥ 3 个星期格」的行；
/// - **星期列**：显式 `Map<列号, 星期>`，不假设连续 7 列、
///   不假设从星期一开头；
/// - **节次行推断**：星期列最小列号左侧为节次列，整列读不到编号时
///   按物理行序递增（全空行不占号）；
/// - **作息三态（E2）**：读到 ≥ 1 个有效时间才构造 periods，否则 null，
///   绝不缩水，由调用方决定是否沿用现有作息；
/// - **节次校验（E1）**：格内自带节次只做绝对校验 1..24，不与
///   detectedSectionCount / 默认节数挂钩；
/// - **课程格三层解析**：第 1 层 [parseCellText] 命中 ≥ 1 条直接用；
///   命中 0 条走第 2 层 [parseGenericCell]，非兜底条目优先，
///   只有兜底条目时计入 [JwxtImportResult.fallbackCount]；
/// - 数据行扫到「注」开头或含「实践课程」的行为止；
/// - 同格/跨格重复（课名+教师+地点+星期+节次完全相同、周次不同）按位合并
///   weekMask；单双周互补课地点不同 → 不同 key → 仍是独立课程。
JwxtImportResult parseJwxtWorkbook(List<List<String?>> rows) {
  // 1. 表头两级识别：先数全表第一级命中，< 3 才启用裸字回退
  int firstLevelHits = 0;
  for (final List<String?> row in rows) {
    for (final String? cell in row) {
      if (cell != null && _matchDayHeader(cell, bare: false) != null) {
        firstLevelHits++;
      }
    }
  }
  final bool bareMode = firstLevelHits < 3;
  int headerRow = -1;
  for (int r = 0; r < rows.length; r++) {
    if (_countDayCells(rows[r], bare: bareMode) >= 3) {
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

  // 2. 星期列 Map（显式列号 → 星期，不假设连续/从周一开始）
  final Map<int, int> dayColumns = <int, int>{};
  final List<String?> headerCells = rows[headerRow];
  for (int c = 0; c < headerCells.length; c++) {
    final int? dayWeek = _matchDayHeader(headerCells[c], bare: bareMode);
    if (dayWeek != null) {
      dayColumns[c] = dayWeek;
    }
  }
  final int leftBound = dayColumns.keys.reduce((int a, int b) => a < b ? a : b);

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
        // 标题可能挤着姓名学号（新版正方），提取纯学期段
        semesterName = extractSemesterName(cell);
        break outer;
      }
    }
  }

  // 4. 数据区边界：「注」开头 / 含「实践课程」的行为止
  int endRow = rows.length;
  for (int r = headerRow + 1; r < rows.length; r++) {
    final String text = _rowText(rows[r]);
    if (text.trim().isEmpty) {
      continue;
    }
    if (text.trim().startsWith('注') || text.contains('实践课程')) {
      endRow = r;
      break;
    }
  }

  // 5. 节次列标签（leftBound 左侧第一个能识别的格）
  final Map<int, _SectionLabel> labels = <int, _SectionLabel>{};
  for (int r = headerRow + 1; r < endRow; r++) {
    final List<String?> row = rows[r];
    if (_rowText(row).trim().isEmpty) {
      continue;
    }
    for (int c = 0; c < leftBound && c < row.length; c++) {
      final String? cell = row[c];
      if (cell == null || cell.trim().isEmpty) {
        continue;
      }
      final _SectionLabel? label = _matchSectionLabel(cell);
      if (label != null) {
        labels[r] = label;
        break;
      }
    }
  }

  // 6. 行节次号推断：有标签用标签编号，否则按物理行序递增
  //（全空行不占号——上面的循环已跳过）。
  //
  // 已知限制：一行代表双节块的表格（如 5 行 = 10 节，每行两节连堂），
  // 行推断会把每行当成单节——信息不足，无法拆分。这类表格的课程格
  // 通常自带 (N-M节)（走第 1 层解析，不受行推断影响）；只有「格内
  // 无节次」的条目才会用推断值，此时宁可错成单节也不丢弃。
  final Map<int, int> rowSectionOf = <int, int>{};
  int nextSection = 1;
  for (int r = headerRow + 1; r < endRow; r++) {
    if (_rowText(rows[r]).trim().isEmpty) {
      continue;
    }
    final int? labeled = labels[r]?.number;
    if (labeled != null) {
      rowSectionOf[r] = labeled;
      nextSection = labeled + 1;
    } else {
      rowSectionOf[r] = nextSection;
      nextSection++;
    }
  }
  final int detectedSectionCount = rowSectionOf.values.isEmpty
      ? 0
      : rowSectionOf.values.reduce((int a, int b) => a > b ? a : b);

  // 7. 作息三态（E2）：读到 ≥ 1 个有效时间才构造 periods；
  // 只有编号没时间 / 连编号都没有 → null（绝不补 --:-- 假时间）。
  final Map<int, Period> periodByIndex = <int, Period>{};
  for (final MapEntry<int, _SectionLabel> e in labels.entries) {
    final (String, String)? time = e.value.time;
    if (time == null) {
      continue;
    }
    final int? index = e.value.number ?? rowSectionOf[e.key];
    if (index == null || index < 1 || index > absMaxSection) {
      continue;
    }
    periodByIndex[index] = Period(index: index, start: time.$1, end: time.$2);
  }
  final List<Period>? periods = periodByIndex.isEmpty
      ? null
      : <Period>[
          for (final int i in (periodByIndex.keys.toList()..sort()))
            periodByIndex[i]!,
        ];

  // 8. 课程格三层解析 → 校验 → 聚合
  // 第 2/3 层条目周次空集 → 填全部周（上界：元信息 totalWeeks，缺省 20）
  final int weeksUpper = totalWeeks ?? 20;
  final Set<int> allWeeks = <int>{
    for (int w = minWeek; w <= maxWeek && w <= weeksUpper; w++) w,
  };
  int skipped = 0;
  int fallbackCount = 0;
  // key 用 record（替代 '|' 拼接字符串），value 累积 weekMask
  final Map<(String, String, String, int, int, int), int> merged =
      <(String, String, String, int, int, int), int>{};
  for (int r = headerRow + 1; r < endRow; r++) {
    final List<String?> row = rows[r];
    if (_rowText(row).trim().isEmpty) {
      continue;
    }
    for (final MapEntry<int, int> column in dayColumns.entries) {
      final int dayWeek = column.value;
      final int col = column.key;
      if (col < 0 || col >= row.length) {
        continue;
      }
      final String? cell = row[col];
      if (cell == null || cell.trim().isEmpty) {
        continue;
      }

      // 课程格分层解析（空行切条目：三行式 → 第 1 层 → 第 2/3 层）
      final (List<_RawEntry> entries, int fallbackAdded) = _parseCellLayers(
        cell,
      );
      fallbackCount += fallbackAdded;

      for (final _RawEntry entry in entries) {
        // 节次：格内自带 → 绝对校验（E1，不与 detectedSectionCount 挂钩）；
        // 格内没有 → 行标签推断值
        final int sectionStart;
        final int sectionEnd;
        if (entry.sectionStart != null && entry.sectionEnd != null) {
          if (entry.sectionStart! < 1 ||
              entry.sectionEnd! > absMaxSection ||
              entry.sectionEnd! < entry.sectionStart!) {
            skipped++;
            continue;
          }
          sectionStart = entry.sectionStart!;
          sectionEnd = entry.sectionEnd!;
        } else {
          final int? rowSection = rowSectionOf[r];
          if (rowSection == null ||
              rowSection < 1 ||
              rowSection > absMaxSection) {
            skipped++;
            continue;
          }
          sectionStart = rowSection;
          sectionEnd = rowSection;
        }
        // 周次：第 1 层空集 = 乱码周次 → 跳过（原语义）；
        // 第 2/3 层空集 = 没识别到 → 填全部周
        Set<int> weeks = entry.weeks;
        if (weeks.isEmpty && entry.fromGeneric) {
          weeks = allWeeks;
        }
        if (weeks.isEmpty || entry.name.isEmpty) {
          skipped++;
          continue;
        }
        final (String, String, String, int, int, int) key = (
          entry.name,
          entry.teacher,
          entry.location,
          dayWeek,
          sectionStart,
          sectionEnd,
        );
        merged[key] = (merged[key] ?? 0) | weekMaskFromWeeks(weeks);
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
      periods: periods,
      usedDefaultPeriods: periods == null,
      detectedSectionCount: detectedSectionCount,
      fallbackCount: fallbackCount,
      error: '未识别到任何课程，请确认选的是教务系统导出的课表',
    );
  }
  return JwxtImportResult(
    courses: courses,
    skippedCount: skipped,
    week1Monday: week1Monday,
    totalWeeks: totalWeeks,
    semesterName: semesterName,
    periods: periods,
    usedDefaultPeriods: periods == null,
    detectedSectionCount: detectedSectionCount,
    fallbackCount: fallbackCount,
  );
}

/// 整行拼接文本（定位表头/元信息/终止行用）。
String _rowText(List<String?> row) {
  return row
      .where((String? cell) => cell != null && cell.trim().isNotEmpty)
      .join(' ');
}
