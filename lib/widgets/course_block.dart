import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/theme/week_grid_dimens.dart';
import 'package:timetable/utils/breakpoints.dart';
import 'package:timetable/utils/timetable_query.dart';

/// 课程块：按 dayWeek / sectionStart~sectionEnd 定位（由 WeekGrid 负责），
/// 这里只负责渲染。空间不够时用省略号。
///
/// 字号来自 [dimens]；平板大块（[windowSize] 为 expanded 且块高足够）时，
/// 信息行从「地点」升级为「地点 · 教师」。判断所需的 [blockHeight] /
/// [rowHeight] 全部由 WeekGrid 传入，本 widget 不读 MediaQuery。
///
/// 移动模式的视觉状态由 WeekGrid 算好传入：被移动的块 [highlighted]
/// （primary 2dp 边框），其余块 [dimmed]（半透明）。
class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.occurrence,
    required this.periods,
    required this.onTap,
    required this.dimens,
    required this.windowSize,
    required this.blockHeight,
    required this.rowHeight,
    this.extraCount = 0,
    this.onLongPress,
    this.highlighted = false,
    this.dimmed = false,
    this.cancelled = false,
  });

  final CourseOccurrence occurrence;
  final List<Period> periods;

  /// 点击；移动模式下由 WeekGrid 传 null（tap 冒泡到网格层算落点）。
  final VoidCallback? onTap;

  /// 长按 → 操作菜单。
  final VoidCallback? onLongPress;

  /// 同格还有几门课（教务导出的分班/选项课）；>0 时右上角显示 "+N" 角标。
  final int extraCount;

  /// 移动模式：本块正是被移动的课（primary 边框高亮）。
  final bool highlighted;

  /// 移动模式：本块不是被移动的课（半透明弱化）。
  final bool dimmed;

  /// 本周停课（来自 override）：整块 0.35 透明 + 课名删除线，
  /// 但**不禁用交互**（用户可能想进详情取消停课）。
  final bool cancelled;

  /// 断点尺寸令牌（字号）。
  final WeekGridDimens dimens;

  /// 窗口断点（expanded 大块才显示教师）。
  final WindowSize windowSize;

  /// 本块的理论渲染高度（节数 × 行高，由 WeekGrid 传入）。
  final double blockHeight;

  /// 单节行高（由 WeekGrid 传入）。
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(occurrence.course.colorValue);
    // 「地点 · 教师」合并行只在 expanded 且块高 >= 2 × 行高时出现。
    // 用理论高度（节数 × rowHeight）判断，不受定位时的 1px 边距修正影响，
    // 两节连堂恰好命中；1 节矮块不显示，窄块（compact/medium）不显示。
    final bool mergedLine =
        windowSize.isExpanded && blockHeight >= 2 * rowHeight;
    final String location = occurrence.location;
    final String teacher = occurrence.course.teacher;
    final String detailLine = mergedLine
        ? (location.isEmpty
              ? teacher
              : teacher.isEmpty
              ? location
              : '$location · $teacher')
        : location;
    Widget content = Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    occurrence.course.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dimens.courseNameSize,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      // 停课：课名划删除线（副标题保持原样）
                      decoration: occurrence.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  if (detailLine.isNotEmpty)
                    Text(
                      detailLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: dimens.courseSubSize,
                      ),
                    ),
                ],
              ),
            ),
            if (extraCount > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '+$extraCount',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: dimens.badgeSize,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (highlighted) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
        child: content,
      );
    }
    if (dimmed) {
      content = Opacity(opacity: 0.5, child: content);
    }
    // 停课：整块 0.35。与移动模式的 dimmed 叠加时近乎隐藏（临时态可接受）
    if (cancelled) {
      content = Opacity(opacity: 0.35, child: content);
    }
    return Padding(padding: const EdgeInsets.all(1), child: content);
  }
}
