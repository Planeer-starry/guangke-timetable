/// 广科 JSON 导入解析器（纯函数，不依赖 flutter）。
///
/// 输入是按周展开的格式 `{"1":[{...}], "2":[...], ..., "20":[...]}`，
/// 严格按 AGENTS.md 5.4 的【两级聚合】，顺序绝对不能颠倒：
/// 1. 第一级：同一周内，把同一 (name, teacher, location, dayWeek) 的
///    连续节次合并成 sectionStart~sectionEnd；
/// 2. 第二级：跨周把 (name, teacher, location, dayWeek, sectionStart, sectionEnd)
///    完全相同的记录合并成一门课，出现过哪些周 → weekMask。
library;

import 'dart:developer' as developer;

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/period_editor.dart';
import 'package:timetable/utils/week_mask.dart';

/// 导入解析结果（含跳过统计与错误提示）。
class ImportResult {
  const ImportResult({
    required this.courses,
    required this.skippedCount,
    this.error,
    this.meta,
    this.periods,
    this.overrides,
  });

  /// 解析出来的课程列表。
  final List<Course> courses;

  /// 被跳过的无法解析条目数（预览页显示「跳过 N 条无法解析的记录」）。
  final int skippedCount;

  /// 解析失败的原因（选错文件 / 未识别到课程）；null 表示成功。
  final String? error;

  /// 文件里携带的学期信息（可选）。教务 JSON 与 App 备份均可能提供，
  /// 校验通过（week1Monday 已设置且 totalWeeks 在 1..maxWeek）才有值；
  /// 解析失败一律为 null，绝不影响课程导入。
  final TimetableMeta? meta;

  /// 文件里携带的作息时间表（可选）。逐项解析并整体校验通过才有值。
  final List<Period>? periods;

  /// App 备份里携带的当周调整（可选）；教务 JSON 恒为 null。
  final List<CourseOverride>? overrides;

  /// 是否可以进入预览。
  bool get isSuccessful => error == null && courses.isNotEmpty;
}

/// 节次合法上界（广科作息 10 节）。
int get _maxSection => Period.defaults.length;

/// 解析课表 JSON，返回课程列表与可选的学期 / 作息 / 当周调整。
///
/// 支持两种格式：
/// 1. 教务 / 爬虫导出的按周展开 JSON `{"1":[...], ..., "20":[...]}`，
///    顶层可附带 `meta` / `periods`（缺失或非法时忽略，行为与旧版一致）；
/// 2. 简课表备份（顶层含 `courses` 键）→ 学期、作息、当周调整一并完整恢复，
///    不走两级聚合。
///
/// 周次以【字典的键】为准；条目里的 week 字段与键冲突时以键为准并记录警告。
/// dayWeek 必须 1..7、section 必须 1..`_maxSection`，越界条目跳过并计数。
ImportResult parseImportedTimetable(Map<String, dynamic> root) {
  if (root.containsKey('courses')) {
    return _parseAppBackup(root);
  }

  final List<_RawEntry> raw = <_RawEntry>[];
  int skipped = 0;
  root.forEach((Object? key, Object? value) {
    final int? week = int.tryParse('$key');
    if (week == null || week < 1 || week > maxWeek) {
      return;
    }
    if (value is! List) {
      skipped++;
      return;
    }
    for (final Object? item in value) {
      if (item is! Map) {
        skipped++;
        continue;
      }
      final List<_RawEntry> entries = _parseEntry(
        item.cast<String, dynamic>(),
        week,
      );
      if (entries.isEmpty) {
        skipped++;
      } else {
        raw.addAll(entries);
      }
    }
  });

  if (raw.isEmpty) {
    return ImportResult(
      courses: <Course>[],
      skippedCount: skipped,
      error: '未识别到任何课程，请检查是否为教务系统导出的 timetable.json',
    );
  }

  return ImportResult(
    courses: _aggregate(raw),
    skippedCount: skipped,
    meta: _tryParseMeta(root['meta']),
    periods: _tryParsePeriods(root['periods']),
  );
}

/// 解析简课表备份（顶层含 courses 键）：学期、作息、当周调整一并带回。
ImportResult _parseAppBackup(Map<String, dynamic> root) {
  try {
    final TimetableData data = TimetableData.fromJson(root);
    if (data.courses.isEmpty) {
      return const ImportResult(
        courses: <Course>[],
        skippedCount: 0,
        error: '备份文件里没有课程，请检查文件是否完整',
      );
    }
    return ImportResult(
      courses: data.courses,
      skippedCount: 0,
      meta: _validOrNull(data.meta),
      periods: validatePeriods(data.periods) == null ? data.periods : null,
      overrides: data.overrides,
    );
  } catch (_) {
    return const ImportResult(
      courses: <Course>[],
      skippedCount: 0,
      error: '备份文件无法解析，请确认是简课表导出的 .json 文件',
    );
  }
}

/// 宽容解析顶层可选 meta：非 Map / 解析异常 / 校验不过 → null（不影响导入）。
TimetableMeta? _tryParseMeta(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  try {
    return _validOrNull(TimetableMeta.fromJson(raw.cast<String, dynamic>()));
  } catch (_) {
    return null;
  }
}

/// meta 有效性：week1Monday 已设置且 totalWeeks 在 1..maxWeek。
TimetableMeta? _validOrNull(TimetableMeta meta) {
  final bool valid =
      meta.week1Monday.year > 1 &&
      meta.totalWeeks >= 1 &&
      meta.totalWeeks <= maxWeek;
  return valid ? meta : null;
}

/// 宽容解析顶层可选 periods：非 List / 任何一项非法 / 整体校验不过 → null。
List<Period>? _tryParsePeriods(Object? raw) {
  if (raw is! List) {
    return null;
  }
  try {
    final List<Period> periods = <Period>[];
    for (final Object? item in raw) {
      if (item is! Map) {
        return null;
      }
      periods.add(Period.fromJson(item.cast<String, dynamic>()));
    }
    return validatePeriods(periods) == null ? periods : null;
  } catch (_) {
    return null;
  }
}

/// 一条从 JSON 解析出的原始上课记录（一个节次一条）。
class _RawEntry {
  const _RawEntry({
    required this.name,
    required this.teacher,
    required this.location,
    required this.dayWeek,
    required this.section,
    required this.week,
  });

  final String name;
  final String teacher;
  final String location;
  final int dayWeek;
  final int section;
  final int week;
}

/// 一块同一周内连续节次的课程（第一级聚合的产物）。
class _Block {
  const _Block({
    required this.name,
    required this.teacher,
    required this.location,
    required this.dayWeek,
    required this.week,
    required this.sectionStart,
    required this.sectionEnd,
  });

  final String name;
  final String teacher;
  final String location;
  final int dayWeek;
  final int week;
  final int sectionStart;
  final int sectionEnd;
}

/// 把一条 JSON 条目解析成【每个节次一条】的原始记录；不合格返回空（跳过）。
List<_RawEntry> _parseEntry(Map<String, dynamic> json, int week) {
  final String name = _firstText(json, const <String>[
    'courseName',
    'kcmc',
    'name',
  ]);
  if (name.isEmpty) {
    return <_RawEntry>[];
  }
  final String teacher = _firstText(json, const <String>[
    'teacher',
    'teacherName',
    'xm',
  ]);
  final String location = _firstText(json, const <String>[
    'classroomName',
    'classroom',
    'room',
    'jxdd',
  ]);

  final int? dayWeek = _firstNumber(
    _pick(json, const <String>['dayWeek', 'xqj']),
  );
  if (dayWeek == null || dayWeek < 1 || dayWeek > 7) {
    return <_RawEntry>[];
  }

  // 条目里若也有 week 字段且与键冲突，以键为准（并记录警告）
  final int? entryWeek = _firstNumber(_pick(json, const <String>['week']));
  if (entryWeek != null && entryWeek != week) {
    developer.log(
      '条目 week=$entryWeek 与周键 $week 冲突，以键为准',
      name: 'timetable_importer',
    );
  }

  // section 解析成【节次集合】，每个节次各生成一条记录
  final Set<int> sections = _parseSections(
    _pick(json, const <String>['whichSection', 'jcs', 'section']),
  );
  final Set<int> valid = sections
      .where((int section) => section >= 1 && section <= _maxSection)
      .toSet();
  if (valid.isEmpty) {
    return <_RawEntry>[];
  }

  return valid
      .map(
        (int section) => _RawEntry(
          name: name,
          teacher: teacher,
          location: location,
          dayWeek: dayWeek,
          section: section,
          week: week,
        ),
      )
      .toList();
}

/// 两级聚合（顺序绝对不能颠倒）。
List<Course> _aggregate(List<_RawEntry> raw) {
  // —— 第一级：同一周内合并连续节次（绝不贪心：{3,5} 拆成 3~3 和 5~5）——
  final Map<String, List<int>> byKey = <String, List<int>>{};
  for (final _RawEntry entry in raw) {
    final String key =
        '${entry.name}|${entry.teacher}|${entry.location}|${entry.dayWeek}|${entry.week}';
    byKey.putIfAbsent(key, () => <int>[]).add(entry.section);
  }
  final List<_Block> blocks = <_Block>[];
  byKey.forEach((String key, List<int> sections) {
    final List<String> parts = key.split('|');
    final List<int> sorted = sections.toSet().toList()..sort();
    int start = sorted.first;
    int prev = start;
    for (int i = 1; i <= sorted.length; i++) {
      final bool hasNext = i < sorted.length;
      if (hasNext && sorted[i] == prev + 1) {
        prev = sorted[i];
        continue;
      }
      blocks.add(
        _Block(
          name: parts[0],
          teacher: parts[1],
          location: parts[2],
          dayWeek: int.parse(parts[3]),
          week: int.parse(parts[4]),
          sectionStart: start,
          sectionEnd: prev,
        ),
      );
      if (hasNext) {
        start = sorted[i];
        prev = start;
      }
    }
  });

  // —— 第二级：跨周合并 → weekMask ——
  final Map<String, Set<int>> byBlockKey = <String, Set<int>>{};
  for (final _Block block in blocks) {
    final String key =
        '${block.name}|${block.teacher}|${block.location}|${block.dayWeek}|${block.sectionStart}|${block.sectionEnd}';
    byBlockKey.putIfAbsent(key, () => <int>{}).add(block.week);
  }
  final List<Course> courses = <Course>[];
  int index = 1;
  byBlockKey.forEach((String key, Set<int> weeks) {
    final List<String> parts = key.split('|');
    courses.add(
      Course(
        id: 'c_${index.toString().padLeft(3, '0')}',
        name: parts[0],
        teacher: parts[1],
        location: parts[2],
        colorValue: colorValueFromName(parts[0]),
        dayWeek: int.parse(parts[3]),
        sectionStart: int.parse(parts[4]),
        sectionEnd: int.parse(parts[5]),
        weekMask: weekMaskFromWeeks(weeks),
      ),
    );
    index++;
  });
  return courses;
}

/// 把 section 字段解析成【节次集合】：
/// `3` → {3}；`"3-4"` → {3,4}；`[3,4]` → {3,4}；`"3"` → {3}；`"1-8,10"` → {1..8,10}。
/// `sectionStart > sectionEnd` 的畸形区间按交换归一。
Set<int> _parseSections(Object? raw) {
  final Set<int> result = <int>{};
  if (raw == null) {
    return result;
  }
  if (raw is num) {
    result.add(raw.toInt());
    return result;
  }
  if (raw is List) {
    for (final Object? item in raw) {
      result.addAll(_parseSections(item));
    }
    return result;
  }
  if (raw is String) {
    // 按逗号/顿号/分号/空白分段，每段独立解析（如 "1-8,10"）
    for (final String part in raw.trim().split(RegExp(r'[,，;；、\s]+'))) {
      if (part.isEmpty) {
        continue;
      }
      final RegExpMatch? range = RegExp(r'^(\d+)\s*[-—~到至]\s*(\d+)$')
          .firstMatch(part);
      if (range != null) {
        final int first = int.parse(range.group(1)!);
        final int last = int.parse(range.group(2)!);
        final int low = first <= last ? first : last;
        final int high = first <= last ? last : first;
        for (int section = low; section <= high; section++) {
          result.add(section);
        }
      } else {
        final int? single = int.tryParse(
          RegExp(r'\d+').firstMatch(part)?.group(0) ?? '',
        );
        if (single != null) {
          result.add(single);
        }
      }
    }
    return result;
  }
  return result;
}

String _firstText(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

Object? _pick(Map<String, dynamic> json, List<String> keys) {
  for (final String key in keys) {
    final Object? value = json[key];
    if (value != null) {
      return value;
    }
  }
  return null;
}

int? _firstNumber(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    final RegExpMatch? match = RegExp(r'\d+').firstMatch(raw);
    return match == null ? null : int.parse(match.group(0)!);
  }
  if (raw is List) {
    for (final Object? item in raw) {
      final int? parsed = _firstNumber(item);
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}
