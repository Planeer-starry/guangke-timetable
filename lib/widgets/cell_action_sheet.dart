import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';

/// 长按课块呼出的操作面板。
///
/// 设计要点：
///
/// 1. **限宽 480**（`showModalBottomSheet` 的 constraints）——
///    手机上接近全宽，平板上自动居中成浮层卡片。改造前是无限宽的
///    底部抽屉，在 848dp 的平板上拉成一整条，内容全挤在左边。
/// 2. **带课程上下文**——长按只是手段，用户真正要确认的是「我在操作哪门课」，
///    所以顶部有课程色条 + 课名 + 时间 + 地点教师，不用靠记忆。
/// 3. **危险操作分组**——删除类用 error 色，并用分隔线单独隔开，降低误触。
class CellActionSheet extends StatelessWidget {
  const CellActionSheet({
    super.key,
    required this.occurrence,
    required this.periods,
    required this.sameNameCount,
  });

  /// 被操作的这节课（已应用 override）。
  final CourseOccurrence occurrence;

  /// 作息，用于把节次换算成具体时间。
  final List<Period> periods;

  /// 同名课程条数；> 1 才显示「删除所有同名课程」。
  final int sameNameCount;

  /// 弹出面板，返回选中的动作标识（'edit' / 'move' / 'delete_named' /
  /// 'delete'）；用户点外部或返回时返回 null。
  static Future<String?> show(
    BuildContext context, {
    required CourseOccurrence occurrence,
    required List<Period> periods,
    required int sameNameCount,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return showModalBottomSheet<String>(
      context: context,
      // 平板上限宽居中；手机（< 480）自然占满，不写死宽度
      constraints: const BoxConstraints(maxWidth: 480),
      backgroundColor: colors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (BuildContext sheetContext) => CellActionSheet(
        occurrence: occurrence,
        periods: periods,
        sameNameCount: sameNameCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color courseColor = Color(occurrence.course.colorValue);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _DragHandle(),
          _CourseHeader(
            occurrence: occurrence,
            periods: periods,
            courseColor: courseColor,
          ),
          const SizedBox(height: 8),
          _ActionRow(
            icon: Icons.edit_outlined,
            title: '编辑',
            subtitle: '修改课名、教师、地点、节次与周次',
            onTap: () => Navigator.of(context).pop('edit'),
          ),
          _ActionRow(
            icon: Icons.open_with,
            title: '移动到…',
            subtitle: '改到其他时段，可选仅本周或所有周',
            onTap: () => Navigator.of(context).pop('move'),
          ),
          // 删除类：单独分组，视觉上与上面隔开
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          if (sameNameCount > 1)
            _ActionRow(
              icon: Icons.delete_sweep_outlined,
              title: '删除所有同名课程',
              subtitle: '共 $sameNameCount 条（教务常把同一门课拆成多条）',
              destructive: true,
              onTap: () => Navigator.of(context).pop('delete_named'),
            ),
          _ActionRow(
            icon: Icons.delete_outline,
            title: '删除这一门',
            subtitle: '只删掉当前这条安排',
            destructive: true,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 顶部拖拽指示条。
class _DragHandle extends StatelessWidget {
  const _DragHandle();

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

/// 课程上下文卡片：色条 + 课名 + 时间 + 地点教师（+ 停课标记）。
class _CourseHeader extends StatelessWidget {
  const _CourseHeader({
    required this.occurrence,
    required this.periods,
    required this.courseColor,
  });

  final CourseOccurrence occurrence;
  final List<Period> periods;
  final Color courseColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String timeLine = _timeLine(occurrence, periods);
    final String metaLine = _metaLine(occurrence);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: courseColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // 左侧课程色条
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: courseColor,
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
                          occurrence.course.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (occurrence.cancelled) ...<Widget>[
                        const SizedBox(width: 8),
                        _CancelledBadge(colors: colors),
                      ],
                    ],
                  ),
                  if (timeLine.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      timeLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (metaLine.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      metaLine,
                      maxLines: 1,
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

  /// 「周一 第5-6节 14:40-16:15」；节次越界（脏数据）时省略时间部分。
  static String _timeLine(CourseOccurrence occurrence, List<Period> periods) {
    final String weekday = _weekdayName(occurrence.dayWeek);
    final String span =
        '第${occurrence.sectionStart}-${occurrence.sectionEnd}节';
    final Period? start = _findPeriod(periods, occurrence.sectionStart);
    final Period? end = _findPeriod(periods, occurrence.sectionEnd);
    if (start == null || end == null) {
      return '周$weekday $span';
    }
    return '周$weekday $span ${start.start}-${end.end}';
  }

  /// 「松3-308 · 苏祉豪」；两者都空时返回空串。
  static String _metaLine(CourseOccurrence occurrence) {
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

  static Period? _findPeriod(List<Period> periods, int index) {
    for (final Period period in periods) {
      if (period.index == index) {
        return period;
      }
    }
    return null;
  }

  static String _weekdayName(int dayWeek) {
    if (dayWeek < 1 || dayWeek > 7) {
      return '?';
    }
    return '一二三四五六日'[dayWeek - 1];
  }
}

/// 停课标记小徽章。
class _CancelledBadge extends StatelessWidget {
  const _CancelledBadge({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '本周停课',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: colors.onErrorContainer,
        ),
      ),
    );
  }
}

/// 一行操作：圆角图标容器 + 标题 + 说明。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color accent = destructive ? colors.error : colors.primary;
    final Color titleColor = destructive ? colors.error : colors.onSurface;

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
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
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
