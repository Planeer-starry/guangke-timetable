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
    required this.onCourseTap,
  });

  final List<Period> periods;
  final List<CourseOccurrence> occurrences;
  final DateTime weekMonday;
  final bool isCurrentWeek;
  final ValueChanged<CourseOccurrence> onCourseTap;

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
    return SizedBox(
      height: headerHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: timeColumnWidth),
          for (int dayWeek = 1; dayWeek <= 7; dayWeek++)
            Expanded(child: _buildHeaderCell(context, dayWeek)),
        ],
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
                color: isToday ? colors.primary : null,
              ),
            ),
            Text(
              '${date.month}/${date.day}',
              style: TextStyle(
                fontSize: 10,
                color: isToday ? colors.primary : colors.outline,
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
    return SizedBox(
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
    );
  }

  Widget _buildDayColumn(BuildContext context, int dayWeek) {
    final List<CourseOccurrence> dayCourses = occurrences
        .where((CourseOccurrence o) => o.dayWeek == dayWeek)
        .toList();
    return Expanded(
      child: Stack(
        children: <Widget>[
          for (final CourseOccurrence occurrence in dayCourses)
            Positioned(
              top: (occurrence.sectionStart - 1) * rowHeight,
              left: 1,
              right: 1,
              height:
                  (occurrence.sectionEnd - occurrence.sectionStart + 1) *
                      rowHeight -
                  2,
              child: CourseBlock(
                occurrence: occurrence,
                periods: periods,
                onTap: () => onCourseTap(occurrence),
              ),
            ),
        ],
      ),
    );
  }
}
