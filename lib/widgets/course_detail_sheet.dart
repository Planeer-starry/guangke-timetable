import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';

/// 课程详情底部弹窗。
Future<void> showCourseDetailSheet(
  BuildContext context, {
  required CourseOccurrence occurrence,
  required List<Period> periods,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(occurrence.course.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      occurrence.course.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('时间：${_timeText(occurrence, periods)}'),
              Text(
                '地点：${occurrence.location.isEmpty ? '未填写' : occurrence.location}',
              ),
              Text(
                '教师：${occurrence.course.teacher.isEmpty ? '未填写' : occurrence.course.teacher}',
              ),
              Text(
                '周次：${formatWeekRanges(weeksFromWeekMask(occurrence.course.weekMask))}',
              ),
              if (occurrence.course.note.isNotEmpty)
                Text('备注：${occurrence.course.note}'),
            ],
          ),
        ),
      );
    },
  );
}

String _timeText(CourseOccurrence occurrence, List<Period> periods) {
  final Period? start = _findPeriod(periods, occurrence.sectionStart);
  final Period? end = _findPeriod(periods, occurrence.sectionEnd);
  final String startText = start?.start ?? '?';
  final String endText = end?.end ?? '?';
  return '${_weekdayName(occurrence.dayWeek)} '
      '第${occurrence.sectionStart}-${occurrence.sectionEnd}节 '
      '$startText-$endText';
}

Period? _findPeriod(List<Period> periods, int index) {
  for (final Period period in periods) {
    if (period.index == index) {
      return period;
    }
  }
  return null;
}

String _weekdayName(int dayWeek) {
  if (dayWeek < 1 || dayWeek > 7) {
    return '?';
  }
  return '一二三四五六日'[dayWeek - 1];
}
