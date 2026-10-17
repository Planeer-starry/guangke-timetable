import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/theme/week_grid_dimens.dart';
import 'package:timetable/utils/breakpoints.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_block.dart';

/// 课表网格：左侧节次列（来自 `meta.periods`，数据驱动）+ 7 个日列。
///
/// 不用 GridView（跨节课无法定位），改用固定行高 + Stack/Positioned：
/// 课程块 `top = (sectionStart-1) * rowHeight`，
/// `height = (sectionEnd - sectionStart + 1) * rowHeight`，
/// 连堂课自然撑高，节数与时间全部来自数据。
///
/// 尺寸全部来自 [dimens]（断点令牌，页面顶层算好传入，本 widget 不读
/// MediaQuery）：
/// - compact / medium：固定行高，屏幕不够高时整体滚动；
/// - expanded（平板）：行高按可用高度动态铺满（clamp 64~100），
///   解决大屏底部大片空白。
class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.periods,
    required this.occurrences,
    required this.weekMonday,
    required this.isCurrentWeek,
    required this.onCellTap,
    required this.dimens,
    required this.windowSize,
  });

  final List<Period> periods;
  final List<CourseOccurrence> occurrences;
  final DateTime weekMonday;
  final bool isCurrentWeek;

  /// 点击课程格；参数是**该格全部课程**（分班/选项课一格多门），
  /// 单门时长度为 1，多门时由上层弹选择列表。
  final ValueChanged<List<CourseOccurrence>> onCellTap;

  /// 断点尺寸令牌。
  final WeekGridDimens dimens;

  /// 窗口断点（透传给 CourseBlock 判断教师行显示）。
  final WindowSize windowSize;

  @override
  Widget build(BuildContext context) {
    if (dimens.rowHeight > 0) {
      return _buildGrid(context, dimens.rowHeight);
    }
    // expanded：行高按可用高度动态算，铺满底部不留白
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxHeight - dimens.headerHeight;
        // 下限 64 保证文字不被压扁；上限 100 防止超大屏行高被拉离谱。
        // 若算出的总高仍超出可用高度（如平板竖屏较矮），交给下方
        // SingleChildScrollView 滚动。
        final double rowHeight = (available / periods.length).clamp(
          64.0,
          100.0,
        );
        return _buildGrid(context, rowHeight);
      },
    );
  }

  Widget _buildGrid(BuildContext context, double rowHeight) {
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
                  _buildTimeColumn(context, rowHeight),
                  for (int dayWeek = 1; dayWeek <= 7; dayWeek++)
                    _buildDayColumn(context, dayWeek, rowHeight),
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
        height: dimens.headerHeight,
        child: Row(
          children: <Widget>[
            SizedBox(width: dimens.timeColumnWidth),
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
                fontSize: dimens.headerFontSize,
                color: isToday ? colors.onPrimaryContainer : colors.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 节次列：数据来自 meta.periods，禁止硬编码。
  Widget _buildTimeColumn(BuildContext context, double rowHeight) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.outlineVariant, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: dimens.timeColumnWidth,
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: dimens.sectionFontSize,
                        ),
                      ),
                      Text(
                        period.start,
                        style: TextStyle(
                          fontSize: dimens.timeFontSize,
                          color: colors.outline,
                        ),
                      ),
                      Text(
                        period.end,
                        style: TextStyle(
                          fontSize: dimens.timeFontSize,
                          color: colors.outline,
                        ),
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

  Widget _buildDayColumn(BuildContext context, int dayWeek, double rowHeight) {
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
    final List<Widget> courseBlocks = <Widget>[
      for (final List<CourseOccurrence> cell in cells.values)
        _buildCourseBlock(cell, rowHeight),
    ];
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
          ...courseBlocks,
        ],
      ),
    );
  }

  /// 同格课程块的定位层：top/height 由节次与行高算出。
  Widget _buildCourseBlock(List<CourseOccurrence> cell, double rowHeight) {
    final CourseOccurrence first = cell.first;
    final int sections = first.sectionEnd - first.sectionStart + 1;
    return Positioned(
      top: (first.sectionStart - 1) * rowHeight,
      left: 1,
      right: 1,
      height: sections * rowHeight - 2,
      child: CourseBlock(
        occurrence: first,
        periods: periods,
        extraCount: cell.length - 1,
        onTap: () => onCellTap(cell),
        dimens: dimens,
        windowSize: windowSize,
        // 理论高度（不减 2px 边距修正），保证两节连堂恰好命中
        // 「块高 >= 2 × 行高」的教师行判断
        blockHeight: sections * rowHeight,
        rowHeight: rowHeight,
      ),
    );
  }
}
