/// 课程弹窗（长按操作面板 / 单击详情面板）共用的外壳与零件。
///
/// 抽出来的原因：这两个面板是**同一个交互家族的两种密度**
/// （长按 = 只给操作，单击 = 先看信息再操作），视觉必须一致，
/// 否则用户会觉得是两个 App。共用一份实现能保证：
/// 限宽、圆角、拖拽条、课程上下文卡片、动作行永远同步。
library;

import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';

/// 弹窗最大宽度：手机（< 480）自然铺满，平板自动居中成浮层。
const BoxConstraints courseSheetConstraints = BoxConstraints(maxWidth: 480);

/// 顶部圆角 28 的弹窗形状。
const RoundedRectangleBorder courseSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
);

/// 顶部拖拽指示条。
class SheetDragHandle extends StatelessWidget {
  const SheetDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// 通用头部卡片：左边条 + 标题（可带徽章）+ 若干说明行。
///
/// 长按面板（课程上下文）、单击面板、导入面板共用同一套外观，
/// 保证「所有底部弹窗第一眼的观感」一致。
class SheetHeaderCard extends StatelessWidget {
  const SheetHeaderCard({
    super.key,
    required this.color,
    required this.title,
    this.lines = const <String>[],
    this.badge,
  });

  /// 左边条与底色着色（课程面板传课程色，导入面板传主色）。
  final Color color;

  final String title;

  /// 说明行（时间、地点教师等）；null 或空串的行会被自动省略。
  final List<String> lines;

  /// 标题右侧的徽章（如「本周停课」）。
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Widget? mark = badge;
    final List<String> visible = <String>[
      for (final String line in lines)
        if (line.isNotEmpty) line,
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (mark != null) ...<Widget>[
                        const SizedBox(width: 8),
                        mark,
                      ],
                    ],
                  ),
                  for (int i = 0; i < visible.length; i++) ...<Widget>[
                    SizedBox(height: i == 0 ? 4 : 2),
                    Text(
                      visible[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 课程上下文卡片：课程色左边条 + 课名（+ 停课徽章）+ 时间 + 地点教师。
///
/// 弹窗第一眼要回答的是「我在看/操作哪门课」，所以这块放在最上方。
class SheetCourseHeader extends StatelessWidget {
  const SheetCourseHeader({
    super.key,
    required this.occurrence,
    required this.periods,
  });

  final CourseOccurrence occurrence;
  final List<Period> periods;

  @override
  Widget build(BuildContext context) {
    return SheetHeaderCard(
      color: Color(occurrence.course.colorValue),
      title: occurrence.course.name,
      lines: <String>[
        courseTimeLine(occurrence, periods),
        courseMetaLine(occurrence),
      ],
      badge: occurrence.cancelled
          ? const SheetBadge(text: '本周停课')
          : null,
    );
  }
}

/// 小徽章（停课等状态标记）。
class SheetBadge extends StatelessWidget {
  const SheetBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colors.onErrorContainer,
        ),
      ),
    );
  }
}

/// 一行操作：44dp 圆角图标容器 + 标题 + 可选说明 + chevron。
class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// true = 用 error 色（删除类）。
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color accent = destructive ? colors.error : colors.primary;
    final String? sub = subtitle;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: destructive ? colors.error : colors.onSurface,
                    ),
                  ),
                  if (sub != null) ...<Widget>[
                    const SizedBox(height: 1),
                    Text(
                      sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// 只读信息行：「标签  值」（详情面板用来放周次、备注）。
class SheetInfoRow extends StatelessWidget {
  const SheetInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组分隔线（普通操作 / 危险操作之间）。
class SheetDivider extends StatelessWidget {
  const SheetDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Divider(
        height: 1,
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

/// 「周一 第5-6节 14:40-16:15」；节次与作息对不上时省略时间部分。
String courseTimeLine(CourseOccurrence occurrence, List<Period> periods) {
  final String weekday = courseWeekdayName(occurrence.dayWeek);
  final String span =
      '第${occurrence.sectionStart}-${occurrence.sectionEnd}节';
  final Period? start = _findPeriod(periods, occurrence.sectionStart);
  final Period? end = _findPeriod(periods, occurrence.sectionEnd);
  if (start == null || end == null) {
    return '周$weekday $span';
  }
  return '周$weekday $span ${start.start}-${end.end}';
}

/// 「松3-308 · 苏祉豪」；两者都空时返回空串（调用方据此省略该行）。
String courseMetaLine(CourseOccurrence occurrence) {
  final String location = occurrence.location.trim();
  final String teacher = occurrence.course.teacher.trim();
  if (location.isEmpty && teacher.isEmpty) {
    return '';
  }
  if (location.isEmpty) {
    return teacher;
  }
  if (teacher.isEmpty) {
    return location;
  }
  return '$location · $teacher';
}

/// 周次文案，如「7-18周」。
String courseWeeksText(CourseOccurrence occurrence) {
  return formatWeekRanges(weeksFromWeekMask(occurrence.course.weekMask));
}

/// 星期中文名；越界返回「?」（防御脏数据）。
String courseWeekdayName(int dayWeek) {
  if (dayWeek < 1 || dayWeek > 7) {
    return '?';
  }
  return '一二三四五六日'[dayWeek - 1];
}

Period? _findPeriod(List<Period> periods, int index) {
  for (final Period period in periods) {
    if (period.index == index) {
      return period;
    }
  }
  return null;
}
