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
/// - expanded（平板）：行高按可用高度动态铺满（clamp 64~100）。
///
/// 移动模式（[isMoving]）：
/// - 网格主体包一层 GestureDetector（[cellAtOffset] 按坐标算落点），
///   空白格也能点——平时**不包**，避免吞掉课块的正常点击；
/// - 课块的 onTap / onLongPress 置 null，tap 手势冒泡到网格层；
/// - 纵向滚动禁用（与点选手势打架）。
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
    this.onCellLongPress,
    this.isMoving = false,
    this.movingCourseId,
    this.onMoveTargetPicked,
  });

  final List<Period> periods;
  final List<CourseOccurrence> occurrences;
  final DateTime weekMonday;
  final bool isCurrentWeek;

  /// 点击课程格；参数是**该格全部课程**（分班/选项课一格多门），
  /// 单门时长度为 1，多门时由上层弹选择列表。
  final ValueChanged<List<CourseOccurrence>> onCellTap;

  /// 长按课程格 → 上层弹操作菜单（编辑 / 移动 / 删除）。
  final ValueChanged<List<CourseOccurrence>>? onCellLongPress;

  /// 断点尺寸令牌。
  final WeekGridDimens dimens;

  /// 窗口断点（透传给 CourseBlock 判断教师行显示）。
  final WindowSize windowSize;

  /// 是否处于「移动课程」模式。
  final bool isMoving;

  /// 正在被移动的课程 id（该块高亮 primary 边框，其余块半透明）。
  final String? movingCourseId;

  /// 移动模式下点击（含空白格）的目标落点回调。
  final void Function(int dayWeek, int sectionStart)? onMoveTargetPicked;

  /// 由网格内点击坐标反算 (星期, 节次)。纯函数，可单测。
  ///
  /// 坐标原点是网格主体（不含表头）左上角；越界坐标 clamp 到
  /// 1..7 / 1..periods，不抛异常。
  static (int, int) cellAtOffset(
    Offset local, {
    required double timeColumnWidth,
    required double dayColumnWidth,
    required double rowHeight,
    required int periods,
  }) {
    final int day = ((local.dx - timeColumnWidth) / dayColumnWidth).floor() + 1;
    final int section = (local.dy / rowHeight).floor() + 1;
    return (day.clamp(1, 7).toInt(), section.clamp(1, periods).toInt());
  }

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
          // LayoutBuilder 拿网格总宽 → 日列宽（7 列均分），
          // 供 cellAtOffset 反算落点
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double dayColumnWidth =
                  (constraints.maxWidth - dimens.timeColumnWidth) / 7;
              return SingleChildScrollView(
                // 移动模式禁纵向滚动，否则和点选落点手势打架
                physics: isMoving ? const NeverScrollableScrollPhysics() : null,
                child: GestureDetector(
                  // opaque：空白格（无子组件的区域）也响应点击
                  behavior: HitTestBehavior.opaque,
                  // ⚠️ 只在移动模式接管点击；平时 null，
                  // 不吞课块的正常点击
                  onTapUp: isMoving && onMoveTargetPicked != null
                      ? (TapUpDetails details) {
                          final (int day, int section) = cellAtOffset(
                            details.localPosition,
                            timeColumnWidth: dimens.timeColumnWidth,
                            dayColumnWidth: dayColumnWidth,
                            rowHeight: rowHeight,
                            periods: periods.length,
                          );
                          onMoveTargetPicked!(day, section);
                        }
                      : null,
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
              );
            },
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

  /// 斑马纹：奇数行（第 2 / 4 / 6 … 节）叠一层极淡的背景。
  ///
  /// 大屏上空网格占比很高，纯背景色上很难用眼睛横着跟住一行；
  /// 2.5% 的 onSurface 叠加几乎看不出色差，但能明显改善行列追踪。
  Color? _rowTint(BuildContext context, int rowIndex) {
    if (rowIndex.isEven) {
      return null;
    }
    return Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.025);
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
              Container(
                height: rowHeight,
                color: _rowTint(context, period.index - 1),
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
          // 颜色取 outlineVariant（亮≈浅灰、暗≈比背景亮一档），深浅色都有结构感；
          // 奇数行再叠一层极淡的斑马纹（与节次列对齐）。
          Positioned.fill(
            child: Column(
              children: <Widget>[
                for (int i = 0; i < periods.length; i++)
                  Container(
                    height: rowHeight,
                    decoration: BoxDecoration(
                      color: _rowTint(context, i),
                      border: Border(right: gridSide, bottom: gridSide),
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
    final bool isMovingThis = isMoving && first.course.id == movingCourseId;
    return Positioned(
      top: (first.sectionStart - 1) * rowHeight,
      left: 1,
      right: 1,
      height: sections * rowHeight - 2,
      child: CourseBlock(
        occurrence: first,
        periods: periods,
        extraCount: cell.length - 1,
        // 移动模式下块自身禁点：InkWell 回调为 null 时不参与手势竞争，
        // tap 冒泡到外层网格 GestureDetector → 算落点
        onTap: isMoving ? null : () => onCellTap(cell),
        onLongPress: isMoving || onCellLongPress == null
            ? null
            : () => onCellLongPress!(cell),
        highlighted: isMovingThis,
        dimmed: isMoving && !isMovingThis,
        cancelled: first.cancelled,
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
