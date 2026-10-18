/// 通用课程格解析器（教务 Excel 导入的第 2/3 层）。
///
/// 背景：不同学校教务导出的课程格格式差异极大。第 1 层
/// （`jwxt_excel_importer.parseCellText` 的正方 `/` 紧凑格式正则）
/// 未命中任何条目时，整格才交给本解析器接管：
///
/// - **第 2 层（启发式）**：切段（换行优先；单行再按空格/斜杠/顿号/
///   分号切）→ 逐段分类（周次 / 节次 / 地点 / 教师形状 / 课名候选）→
///   组装消歧。出现多个周次段视为一格多课，以周次段为锚切分。
/// - **第 3 层（兜底）**：第 2 层拿不到课名时，整格文本直接当课名
///   （换行并成空格、截断 40 字），周次/节次留空交给调用方补全，
///   条目标记 [GenericCellEntry.fallback]，预览页据此提示
///   「导入后可手动补全地点与教师」。宁可粗糙也要出东西，
///   绝不静默丢弃。
///
/// [parseWeeksText] 从 `jwxt_excel_importer` **原样迁移**至此
/// （实现一字未改；本解析器的周次段判定依赖它），
/// `jwxt_excel_importer` 通过 `export ... show parseWeeksText`
/// 保持原 import 路径兼容，既有测试（A 组）无需改动。
library;

import 'package:timetable/utils/week_mask.dart';

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

/// 第 2/3 层解析出的一条课程记录。
///
/// 与第 1 层 `JwxtCellEntry` 的区别：节次可空（null = 格内没识别到，
/// 由调用方用行标签推断）、周次可空（空集合 = 没识别到，由调用方
/// 填全部周）、带兜底标记。
class GenericCellEntry {
  const GenericCellEntry({
    required this.name,
    required this.sectionStart,
    required this.sectionEnd,
    required this.weeks,
    required this.location,
    required this.teacher,
    this.fallback = false,
  });

  /// 课程名。
  final String name;

  /// 节次起；null = 格内没识别到，交给调用方用行标签推断。
  final int? sectionStart;

  /// 节次止；null 同上。
  final int? sectionEnd;

  /// 周次集合；空 = 没识别到，由调用方填全部周（1..totalWeeks）。
  final Set<int> weeks;

  /// 地点；没识别到为空串。
  final String location;

  /// 教师；没识别到为空串。
  final String teacher;

  /// 是否走了第 3 层兜底（预览页警示「导入后可手动补全」用）。
  final bool fallback;
}

/// 解析一个课程格（第 2/3 层；第 1 层未命中时由调用方转入）。
///
/// 返回空列表 = 格子没有可用内容（空白）；
/// 返回 [GenericCellEntry.fallback] = true 的条目 = 第 3 层兜底。
List<GenericCellEntry> parseGenericCell(String cellText) {
  final String trimmed = cellText.trim();
  if (trimmed.isEmpty) {
    return const <GenericCellEntry>[];
  }
  final List<String> rawSegments = _splitSegments(trimmed);
  if (rawSegments.isEmpty) {
    return const <GenericCellEntry>[];
  }

  // 拆括号展开：`高等数学[1-16周]` → 「高等数学」+「1-16周」
  final List<String> segments = <String>[];
  for (final String segment in rawSegments) {
    final (String, String)? unwrapped = _tryUnwrapBrackets(segment);
    if (unwrapped == null) {
      segments.add(segment);
    } else {
      final (String prefix, String inner) = unwrapped;
      if (prefix.isNotEmpty) {
        segments.add(prefix);
      }
      segments.add(inner);
    }
  }

  final List<_Seg> segs = <_Seg>[
    for (final String segment in segments) _classify(segment),
  ];

  // 一格多课：≥ 2 个周次段 → 以周次段为锚切分；
  // 任一组拿不到课名 → 放弃分组，整格按一条处理（不硬猜）
  final List<int> weekIndexes = <int>[
    for (int i = 0; i < segs.length; i++)
      if (segs[i].kind == _SegKind.weeks) i,
  ];
  if (weekIndexes.length >= 2) {
    final List<GenericCellEntry?> grouped = <GenericCellEntry?>[
      for (final int anchor in weekIndexes) _assembleAnchored(segs, anchor),
    ];
    if (grouped.every((GenericCellEntry? entry) => entry != null)) {
      return grouped.cast<GenericCellEntry>();
    }
  }

  final GenericCellEntry? whole = _assembleWhole(segs);
  if (whole != null) {
    return <GenericCellEntry>[whole];
  }
  return <GenericCellEntry>[_fallbackEntry(trimmed)];
}

// ───────────────────────── 切段 ─────────────────────────

/// 切段：先按换行切；只有一行时再按 空格/斜杠/顿号/分号 切。
///
/// 多行不按空格切——课名可能含空格（「大学 英语」）。
List<String> _splitSegments(String text) {
  final List<String> byLine = text
      .split(RegExp(r'\r\n|\r|\n'))
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();
  if (byLine.length > 1) {
    return byLine;
  }
  if (byLine.isEmpty) {
    return const <String>[];
  }
  return byLine.single
      .split(RegExp(r'[\s/、;；]+'))
      .map((String piece) => piece.trim())
      .where((String piece) => piece.isNotEmpty)
      .toList();
}

/// 括号包裹形：`前缀[内容]` / `前缀（内容）`，且内容是节次或周次。
final RegExp _bracketPattern = RegExp(
  r'^(.{1,40})[（(\[]([^（）()\[\]]{1,24})[）)\]]$',
);

/// 拆出 (前缀, 括号内)；内容不是节次/周次则不拆（如「课名(备注)」）。
(String, String)? _tryUnwrapBrackets(String segment) {
  final RegExpMatch? match = _bracketPattern.firstMatch(segment);
  if (match == null) {
    return null;
  }
  final String prefix = match.group(1)!.trim();
  final String inner = match.group(2)!.trim();
  if (prefix.isEmpty || inner.isEmpty) {
    return null;
  }
  final bool innerIsSection = _matchSection(inner) != null;
  final bool innerIsWeeks = _matchWeeks(inner) != null;
  if (innerIsSection || innerIsWeeks) {
    return (prefix, inner);
  }
  return null;
}

// ───────────────────────── 段分类 ─────────────────────────

/// 段类型。
enum _SegKind { weeks, section, location, teacher, name }

/// 已分类的段（记录判定产物，避免二次解析）。
class _Seg {
  const _Seg.weeks(this.text, this.weeks)
    : kind = _SegKind.weeks,
      sectionStart = null,
      sectionEnd = null,
      location = null;

  const _Seg.section(this.text, this.sectionStart, this.sectionEnd)
    : kind = _SegKind.section,
      weeks = null,
      location = null;

  const _Seg.location(this.text, this.location)
    : kind = _SegKind.location,
      weeks = null,
      sectionStart = null,
      sectionEnd = null;

  const _Seg.teacher(this.text)
    : kind = _SegKind.teacher,
      weeks = null,
      sectionStart = null,
      sectionEnd = null,
      location = null;

  const _Seg.name(this.text)
    : kind = _SegKind.name,
      weeks = null,
      sectionStart = null,
      sectionEnd = null,
      location = null;

  final _SegKind kind;

  /// 原段文本。
  final String text;

  /// 周次集合（kind == weeks 时非空）。
  final Set<int>? weeks;

  /// 节次起（kind == section 时非空）。
  final int? sectionStart;

  /// 节次止。
  final int? sectionEnd;

  /// 地点显示文本（kind == location 时非空；「校区 楼栋」取楼栋）。
  final String? location;
}

/// 段分类：优先级 周次 > 节次 > 地点 > 教师形状，其余归课名候选。
_Seg _classify(String text) {
  final Set<int>? weeks = _matchWeeks(text);
  if (weeks != null) {
    return _Seg.weeks(text, weeks);
  }
  final (int, int)? section = _matchSection(text);
  if (section != null) {
    return _Seg.section(text, section.$1, section.$2);
  }
  final String? location = _matchLocation(text);
  if (location != null) {
    return _Seg.location(text, location);
  }
  if (_isTeacherShaped(text)) {
    return _Seg.teacher(text);
  }
  return _Seg.name(text);
}

/// 周次段判定：
/// 1) 括号换空格后 [parseWeeksText] 解析出非空集合（覆盖 `1-16周(双)`）；
/// 2) 整段长度 ≤ 30（避免把长课名误判）；
/// 3) 纯度：去掉 周/单/双 后每个片段都是纯数字或数字区间
///    （把 `(1-2节)11-14周` 这类混合段挡在周次之外）。
Set<int>? _matchWeeks(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.length > 30) {
    return null;
  }
  final String prepared = trimmed.replaceAll(RegExp(r'[（）()]'), ' ');
  final Set<int> weeks = parseWeeksText(prepared);
  if (weeks.isEmpty) {
    return null;
  }
  final String cleaned = prepared.replaceAll(RegExp(r'[周单双]'), ' ');
  for (final String piece in cleaned.split(RegExp(r'[,，、;；\s]+'))) {
    if (piece.isEmpty) {
      continue;
    }
    if (!RegExp(r'^\d+([-–~—到至]\d+)?$').hasMatch(piece)) {
      return null;
    }
  }
  return weeks;
}

/// 节次段判定：`3-4节` / `第3-4节` / `第3节`（单节 start == end）。
(int, int)? _matchSection(String text) {
  final String trimmed = text.trim();
  final RegExpMatch? range = RegExp(r'^(\d+)\s*[-–~]\s*(\d+)\s*节$')
      .firstMatch(trimmed);
  if (range != null) {
    return (int.parse(range.group(1)!), int.parse(range.group(2)!));
  }
  final RegExpMatch? single = RegExp(r'^第\s*(\d+)(?:\s*[-–~]\s*(\d+))?\s*节$')
      .firstMatch(trimmed);
  if (single != null) {
    final int start = int.parse(single.group(1)!);
    final int end = single.group(2) == null
        ? start
        : int.parse(single.group(2)!);
    return (start, end);
  }
  return null;
}

/// 地点形状（无空格单形）：
/// - 含关键词 楼|室|教室|馆|场|机房|实验|校区|网教|线上|图书馆；
/// - `A302` / `B12`（1~2 字母 + 数字）；
/// - `3-308` / `A3-308`（规格原式：字母可选 + 数字[-#]数字，可多组）；
/// - `教1-201` / `松6-604`（1~2 汉字 + 数字[-#]数字，中文楼栋）。
bool _isLocationShape(String text) {
  if (text.isEmpty) {
    return false;
  }
  if (RegExp(r'楼|室|教室|馆|场|机房|实验|校区|网教|线上|图书馆').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^[A-Za-z]{1,2}\d{1,4}$').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^[A-Za-z]?\d{1,3}([-#]\d{1,4})+$').hasMatch(text)) {
    return true;
  }
  if (RegExp(r'^[\u4e00-\u9fa5]{1,2}\d{1,3}[-#]\d{1,4}$').hasMatch(text)) {
    return true;
  }
  return false;
}

/// 地点段判定：本身是地点形状，或「校区 楼栋」带空格形式
/// （最后一个空格后是地点形状 → 整段算地点，显示取后半，
/// 对齐第 1 层 `_shortLocation` 的「松山湖 松6-604 → 松6-604」）。
String? _matchLocation(String text) {
  final String trimmed = text.trim();
  if (_isLocationShape(trimmed)) {
    return trimmed;
  }
  final int lastSpace = trimmed.lastIndexOf(' ');
  if (lastSpace != -1) {
    final String tail = trimmed.substring(lastSpace + 1).trim();
    if (tail.isNotEmpty && _isLocationShape(tail)) {
      return tail;
    }
  }
  return null;
}

/// 教师形状：2~4 个纯汉字，且不含 周/节/楼/室/馆/场（时间地点特征词）。
///
/// 注意这只是「形状」而非结论——`高等数学` 也满足形状，
/// 由组装阶段消歧（见 [_resolveNameTeacher]）。
bool _isTeacherShaped(String text) {
  if (!RegExp(r'^[\u4e00-\u9fa5]{2,4}$').hasMatch(text)) {
    return false;
  }
  return !RegExp(r'[周节楼室馆场]').hasMatch(text);
}

// ───────────────────────── 组装 ─────────────────────────

/// 课名 / 教师消歧（教务格的典型段序是「课名 [教师] 周次 地点」）：
///
/// - 课名候选非空 → 课名 = 候选拼接（空格连接，保住「大学 英语」），
///   教师 = 教师形状段的最后一个；
/// - 课名候选为空且教师形状段只有 1 个 → 该段当课名，教师空
///   （只有课名的格：「高等数学」）；
/// - 课名候选为空且教师形状段 ≥ 2 → 最后一个是教师，
///   其余拼接为课名（「高等数学 张三」：高等数学=课名、张三=教师）。
///
/// 返回 (课名, 教师)；课名为空 = 组装失败（进第 3 层）。
(String, String) _resolveNameTeacher(List<_Seg> segs) {
  final List<String> names = <String>[
    for (final _Seg seg in segs)
      if (seg.kind == _SegKind.name) seg.text,
  ];
  final List<String> teachers = <String>[
    for (final _Seg seg in segs)
      if (seg.kind == _SegKind.teacher) seg.text,
  ];
  if (names.isEmpty) {
    if (teachers.length == 1) {
      return (teachers.single, '');
    }
    if (teachers.length >= 2) {
      return (
        teachers.sublist(0, teachers.length - 1).join(' '),
        teachers.last,
      );
    }
    return ('', '');
  }
  return (names.join(' '), teachers.isEmpty ? '' : teachers.last);
}

/// 整格组装成一条（单周次段 / 无周次段 / 锚点分组失败回退 共用）。
GenericCellEntry? _assembleWhole(List<_Seg> segs) {
  final Set<int> weeks = <int>{};
  int? sectionStart;
  int? sectionEnd;
  final List<String> locations = <String>[];
  for (final _Seg seg in segs) {
    switch (seg.kind) {
      case _SegKind.weeks:
        weeks.addAll(seg.weeks!);
      case _SegKind.section:
        if (sectionStart == null) {
          sectionStart = seg.sectionStart;
          sectionEnd = seg.sectionEnd;
        }
      case _SegKind.location:
        locations.add(seg.location!);
      case _SegKind.teacher:
      case _SegKind.name:
        break;
    }
  }
  final (String, String) resolved = _resolveNameTeacher(segs);
  if (resolved.$1.isEmpty) {
    return null;
  }
  return GenericCellEntry(
    name: resolved.$1,
    sectionStart: sectionStart,
    sectionEnd: sectionEnd,
    weeks: weeks,
    location: locations.join(' '),
    teacher: resolved.$2,
  );
}

/// 锚点组装：以 [anchor] 位置的周次段为一门课的核心。
///
/// - **往前**收连续的教师/课名段（节次段记录后跳过继续——
///   覆盖「第3-4节 高等数学 1-16周」的节次在课名前的排布）；
/// - **往后**收到下一个周次段前的全部段（地点/教师/节次）；
///   青果典型序「课名 教师 周次 地点」的地点紧随周次，归本组。
GenericCellEntry? _assembleAnchored(List<_Seg> segs, int anchor) {
  final List<_Seg> before = <_Seg>[];
  int? sectionStart;
  int? sectionEnd;
  for (int j = anchor - 1; j >= 0; j--) {
    final _Seg seg = segs[j];
    if (seg.kind == _SegKind.teacher || seg.kind == _SegKind.name) {
      before.insert(0, seg);
    } else if (seg.kind == _SegKind.section && sectionStart == null) {
      sectionStart = seg.sectionStart;
      sectionEnd = seg.sectionEnd;
    } else {
      break;
    }
  }

  final List<_Seg> after = <_Seg>[];
  for (int j = anchor + 1; j < segs.length; j++) {
    if (segs[j].kind == _SegKind.weeks) {
      break;
    }
    after.add(segs[j]);
  }

  final (String, String) resolved = _resolveNameTeacher(before);
  String name = resolved.$1;
  String teacher = resolved.$2;
  if (teacher.isEmpty) {
    for (final _Seg seg in after) {
      if (seg.kind == _SegKind.teacher) {
        teacher = seg.text;
        break;
      }
    }
  }
  if (name.isEmpty) {
    return null;
  }

  final List<String> locations = <String>[];
  for (final _Seg seg in after) {
    if (seg.kind == _SegKind.section && sectionStart == null) {
      sectionStart = seg.sectionStart;
      sectionEnd = seg.sectionEnd;
    }
    if (seg.kind == _SegKind.location) {
      locations.add(seg.location!);
    }
  }

  return GenericCellEntry(
    name: name,
    sectionStart: sectionStart,
    sectionEnd: sectionEnd,
    weeks: segs[anchor].weeks!,
    location: locations.join(' '),
    teacher: teacher,
  );
}

/// 第 3 层兜底：整格文本当课名（换行并空格、截断 40 字），
/// 周次/节次留空（调用方填全部周 / 行标签推断），标记 fallback。
GenericCellEntry _fallbackEntry(String trimmed) {
  String name = trimmed.replaceAll(RegExp(r'\s+'), ' ');
  if (name.length > 40) {
    name = name.substring(0, 40);
  }
  return GenericCellEntry(
    name: name,
    sectionStart: null,
    sectionEnd: null,
    weeks: const <int>{},
    location: '',
    teacher: '',
    fallback: true,
  );
}
