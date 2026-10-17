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
  });

  final CourseOccurrence occurrence;
  final List<Period> periods;
  final VoidCallback onTap;

  /// 同格还有几门课（教务导出的分班/选项课）；>0 时右上角显示 "+N" 角标。
  final int extraCount;

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
    // 用理论高度（节数 × rowHeight）判断，不受定位时的 1px 内边距修正影响，
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
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
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
      ),
    );
  }
}
