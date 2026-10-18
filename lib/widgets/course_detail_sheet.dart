import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';

/// 课程详情底部弹窗。
///
/// [onEdit] / [onDelete] 传入时底部显示操作按钮（可空 = 不显示）。
/// 点击按钮会**先关掉本弹窗再调用回调**，避免编辑页 / 删除确认框
/// 被本弹窗遮住。
///
/// 本周调整（J3）：[currentWeek] 传入（非 null）时显示「本周停课 /
/// 取消本周调整」行——[hasOverrideThisWeek] 决定是否并排「取消本周调整」；
/// 已停课（occurrence.cancelled）时顶部显示「本周已停课」标签，
/// 且保留「取消本周调整」作为恢复上课的入口（不再显示「本周停课」）。
Future<void> showCourseDetailSheet(
  BuildContext context, {
  required CourseOccurrence occurrence,
  required List<Period> periods,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  int? currentWeek,
  bool hasOverrideThisWeek = false,
  VoidCallback? onCancelThisWeek,
  VoidCallback? onClearWeekAdjust,
}) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context) {
      // 「本周停课」：本周参数齐 + 未停课（停课的课再停一次无意义）
      final bool showCancelThisWeek =
          currentWeek != null &&
          !occurrence.cancelled &&
          onCancelThisWeek != null;
      // 「取消本周调整」：已有 override（改时间地点/停课）时提供；
      // cancelled 兜底也显示（停课必然有 override，不依赖调用方传参正确）
      final bool showClearWeekAdjust =
          currentWeek != null &&
          onClearWeekAdjust != null &&
          (hasOverrideThisWeek || occurrence.cancelled);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 已停课：顶部标签
              if (occurrence.cancelled) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: const Text('本周已停课'),
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .errorContainer,
                    labelStyle: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
              // 「本周调整」行在「编辑 / 删除」行上方
              if (showCancelThisWeek || showClearWeekAdjust) ...<Widget>[
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    if (showCancelThisWeek)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onCancelThisWeek();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                          ),
                          icon: const Icon(Icons.event_busy),
                          label: const Text('本周停课'),
                        ),
                      ),
                    if (showCancelThisWeek && showClearWeekAdjust)
                      const SizedBox(width: 12),
                    if (showClearWeekAdjust)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onClearWeekAdjust();
                          },
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('取消本周调整'),
                        ),
                      ),
                  ],
                ),
              ],
              if (onEdit != null || onDelete != null) ...<Widget>[
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    if (onEdit != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onEdit();
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                      ),
                    if (onEdit != null && onDelete != null)
                      const SizedBox(width: 12),
                    if (onDelete != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            onDelete();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      ),
                  ],
                ),
              ],
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
