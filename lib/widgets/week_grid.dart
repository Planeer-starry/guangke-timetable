import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_block.dart';

/// 课表网格：左侧节次列（来自 `meta.periods`，数据驱动）+ 7 个日列。
///
/// 不用 GridView（跨节课无法定位），改用固定行高 + Stack/Positioned：
/// 课程块 `top = (sectionStart-1) * rowHeight`，
/// `height = (sectionEnd - sectionStart + 1) * rowHeight`，
/// 连堂课自然撑高，节数与时间全部来自数据、零硬编码。
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.periods,
    required this.occurrences,
    required this.weekMonday,
    required this.isCurrentWeek,
    required this.onCellTap,
  });

  final List<Period> periods;
  final List<CourseOccurrence> occurrences;
  final DateTime weekMonday;
  final bool isCurrentWeek;

  /// 点击课程格；参数是**该格全部课程**（分班/选项课一格多门），
  /// 单门时长度为 1，多门时由上层弹选择列表。
  final ValueChanged<List<CourseOccurrence>> onCellTap;

  /// 每一节的高度。
  static const double rowHeight = 64;

  /// 左侧节次列宽。
  static const double timeColumnWidth = 48;

  /// 表头高度。
  static const double headerHeight = 44;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(context),
        Expanded(
          child: SingleChildScrollView(
            child: SizedBox(
              height: periods.length * rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildTimeColumn(context),
                  for (int dayWeek = 1; dayWeek <= 7; dayWeek++)
                    _buildDayColumn(context, dayWeek),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: SizedBox(
        height: headerHeight,
        child: Row(
          children: <Widget>[
            const SizedBox(width: timeColumnWidth),
            for (int dayWeek = 1; dayWeek <= 7; dayWeek++)
              Expanded(child: _buildHeaderCell(context, dayWeek)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, int dayWeek) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final DateTime date = weekMonday.add(Duration(days: dayWeek - 1));
    final DateTime now = DateTime.now();
    final bool isToday =
        isCurrentWeek &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final List<String> names = <String>['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: Container(
        decoration: isToday
            ? BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              names[dayWeek - 1],
              style: TextStyle(
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? colors.onPrimaryContainer : null,
              ),
            ),
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                fontSize: 10,
                color: isToday ? colors.onPrimaryContainer : colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 节次列：数据来自 meta.periods，禁止硬编码。
  Widget _buildTimeColumn(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: timeColumnWidth,
        child: Column(
          children: <Widget>[
            for (final Period period in periods)
              SizedBox(
                height: rowHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        '${period.index}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        period.start,
                        style: TextStyle(fontSize: 9, color: colors.outline),
                      ),
                      Text(
                        period.end,
                        style: TextStyle(fontSize: 9, color: colors.outline),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayColumn(BuildContext context, int dayWeek) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final BorderSide gridSide = BorderSide(
      color: colors.outlineVariant,
      width: 0.5,
    );
    final List<CourseOccurrence> dayCourses = occurrences
        .where((CourseOccurrence o) => o.dayWeek == dayWeek)
        .toList();
    // 同格多课（教务导出的分班/选项课）：按 (节次起, 节止) 分组，
    // 主显第一门 + "+N" 角标；部分重叠的课保持原绘制顺序（后画盖前画）。
    // key 用 Dart record（不再用 '|' 拼字符串）。
    final Map<(int, int), List<CourseOccurrence>> cells =
        <(int, int), List<CourseOccurrence>>{};
    for (final CourseOccurrence occurrence in dayCourses) {
      cells
          .putIfAbsent((
            occurrence.sectionStart,
            occurrence.sectionEnd,
          ), () => <CourseOccurrence>[])
          .add(occurrence);
    }
    return Expanded(
      child: Stack(
        children: <Widget>[
          // 底层网格：每节一个 cell 画右/下边线，7 列叠加形成完整行列，
          // 颜色取 outlineVariant（亮≈浅灰、暗≈比背景亮一档），深浅色都有结构感
          Positioned.fill(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < periods.length; i++)
                  SizedBox(
                    height: rowHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(right: gridSide, bottom: gridSide),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (final List<CourseOccurrence> cell in cells.values)
            Positioned(
              top: (cell.first.sectionStart - 1) * rowHeight,
              left: 1,
              right: 1,
              height:
                  (cell.first.sectionEnd - cell.first.sectionStart + 1) *
                      rowHeight -
                  2,
              child: CourseBlock(
                occurrence: cell.first,
                periods: periods,
                extraCount: cell.length - 1,
                onTap: () => onCellTap(cell),
              ),
            ),
        ],
      ),
    );
  }
}
