import 'dart:convert';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_math.dart';

/// 「一周总课表」小组件的一个格子（纯展示数据，由 Dart 算好）。
class WeekCell {
  const WeekCell({
    required this.text,
    required this.color,
    required this.extra,
  });

  /// 显示的课名（同格多课时取排序后第一门）。
  final String text;

  /// 课程色（ARGB int）。
  final int color;

  /// 同格还有几门课；>0 时格子显示「+N」。
  final int extra;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    // Kotlin Int 是 32 位：先转字符串，Kotlin 侧 toLong 再 toInt 保位模式
    'color': color.toString(),
    'extra': extra,
  };
}

/// 网格的一行（固定 5 行：1-2 / 3-4 / 5-6 / 7-8 / 9-10）。
class WeekRow {
  const WeekRow({required this.label, required this.cells});

  final String label;

  /// 固定 7 个元素（周一..周日），没课为 null。
  final List<WeekCell?> cells;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'cells': cells.map((WeekCell? cell) => cell?.toJson()).toList(),
  };
}

/// 一周的网格快照。
class WeekSnapshot {
  const WeekSnapshot({
    required this.weekStart,
    required this.weekLabel,
    required this.dates,
    required this.rows,
  });

  /// 该周周一（本地日期）。
  final DateTime weekStart;

  /// 周次文案，如「第6周」。
  final String weekLabel;

  /// 7 个「M/d」日期（无前导零）。
  final List<String> dates;

  /// 固定 5 行。
  final List<WeekRow> rows;

  /// 与 Kotlin `LocalDate.parse` 对齐的日期键：`2026-10-12`。
  String get weekStartKey =>
      '${weekStart.year.toString().padLeft(4, '0')}-'
      '${weekStart.month.toString().padLeft(2, '0')}-'
      '${weekStart.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'weekStart': weekStartKey,
    'weekLabel': weekLabel,
    'dates': dates,
    'rows': rows.map((WeekRow row) => row.toJson()).toList(),
  };
}

/// 固定的 5 个双节块行标签。
const List<String> weekRowLabels = <String>['1-2', '3-4', '5-6', '7-8', '9-10'];

/// 序列化成 `week_grids` 键的 JSON（顶层 `{"weeks": [...]}`）。
String weekGridsEncode(List<WeekSnapshot> snapshots) {
  return jsonEncode(<String, dynamic>{
    'weeks': snapshots.map((WeekSnapshot s) => s.toJson()).toList(),
  });
}

/// 生成 [now] 所在周起 [count] 周的网格快照（纯函数，供单测）。
///
/// 为什么存 3 周而不是只存本周：跨周 0 点触发的是 Android 的 onUpdate
/// （不重跑 Dart），按日期挑周才能跨周自动正确——否则下周一凌晨组件
/// 会一直显示上一周的课表。
///
/// - 课程映射到双节块行号：`rowIndex = ((sectionStart - 1) ~/ 2).clamp(0, 4)`；
///   跨多个双节块的课（如 3-6 节）在涉及的每一行都填；
/// - 同格多课：按课名排序取第一门作 text，其余累加到 extra；
/// - override 已生效（复用 coursesForWeek）。
List<WeekSnapshot> weekSnapshots(
  TimetableData data,
  DateTime now, {
  int count = 3,
}) {
  if (!data.semesterConfigured) {
    return const <WeekSnapshot>[];
  }
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime thisMonday = today.subtract(Duration(days: today.weekday - 1));
  final List<WeekSnapshot> result = <WeekSnapshot>[];
  for (int i = 0; i < count; i++) {
    final DateTime monday = thisMonday.add(Duration(days: 7 * i));
    final int week = weekOfDate(
      monday,
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
    result.add(_snapshotForWeek(data, monday, week));
  }
  return result;
}

WeekSnapshot _snapshotForWeek(TimetableData data, DateTime monday, int week) {
  // 周视图小组件无停课态渲染（Kotlin 侧无 cancelled 概念），
  // 停课的课直接不显示；App 内周网格仍显示半透明停课块
  final List<CourseOccurrence> occurrences = coursesForWeek(
    data,
    week,
  ).where((CourseOccurrence o) => !o.cancelled).toList();

  // (行, 星期) → 该格课程列表；同格多课在转 WeekCell 时聚合
  final Map<(int, int), List<CourseOccurrence>> grid =
      <(int, int), List<CourseOccurrence>>{};
  for (final CourseOccurrence o in occurrences) {
    final int rowStart = ((o.sectionStart - 1) ~/ 2).clamp(0, 4);
    final int rowEnd = ((o.sectionEnd - 1) ~/ 2).clamp(0, 4);
    for (int row = rowStart; row <= rowEnd; row++) {
      grid.putIfAbsent((row, o.dayWeek), () => <CourseOccurrence>[]).add(o);
    }
  }

  final List<WeekRow> rows = <WeekRow>[];
  for (int r = 0; r < weekRowLabels.length; r++) {
    final List<WeekCell?> cells = <WeekCell?>[];
    for (int dayWeek = 1; dayWeek <= 7; dayWeek++) {
      final List<CourseOccurrence>? cellCourses = grid[(r, dayWeek)];
      if (cellCourses == null || cellCourses.isEmpty) {
        cells.add(null);
        continue;
      }
      // 同格多课：按课名排序，第一门做主显，其余计入 extra
      final List<CourseOccurrence> sorted = cellCourses.toList()
        ..sort(
          (CourseOccurrence a, CourseOccurrence b) =>
              a.course.name.compareTo(b.course.name),
        );
      cells.add(
        WeekCell(
          text: sorted.first.course.name,
          color: sorted.first.course.colorValue,
          extra: sorted.length - 1,
        ),
      );
    }
    rows.add(WeekRow(label: weekRowLabels[r], cells: cells));
  }

  return WeekSnapshot(
    weekStart: monday,
    weekLabel: '第$week周',
    dates: <String>[
      for (int d = 0; d < 7; d++)
        '${monday.add(Duration(days: d)).month}/${monday.add(Duration(days: d)).day}',
    ],
    rows: rows,
  );
}
