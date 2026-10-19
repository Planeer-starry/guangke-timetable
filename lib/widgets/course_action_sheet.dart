import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 课程操作面板 —— **单击与长按共用同一个面板**。
///
/// 历史：早先单击弹「详情」、长按弹「操作」，两个面板的动作交叉重复
/// （都有编辑和删除，但「移动到…」只在长按、「本周停课」只在单击），
/// 用户得记住哪个手势能做什么。现在合并成一个：一次看全，点哪个都行。
///
/// 分组（从上到下按「改 → 本周 → 删」的危险度递增排列）：
///
/// ```
/// 课程上下文卡片（色条 + 课名 + 时间 + 地点教师 + 停课徽章）
/// 周次 / 备注
/// ────────────
/// 编辑            改课程本身
/// 移动到…         改这一节的位置
/// ────────────     ← 仅在「本周」信息可用时出现
/// 本周停课        只改本周
/// 取消本周调整     撤回本周的改动
/// ────────────
/// 删除所有同名课程   危险，排最后
/// 删除这一门
/// ```
///
/// 高屏（手机竖屏）内容可能略长于弹窗高度，内部可滚动。
class CourseActionSheet extends StatelessWidget {
  const CourseActionSheet({
    super.key,
    required this.occurrence,
    required this.periods,
    required this.sameNameCount,
    this.currentWeek,
    this.hasOverrideThisWeek = false,
  });

  /// 被操作的这节课（已应用 override）。
  final CourseOccurrence occurrence;

  /// 作息，用于把节次换算成具体时间。
  final List<Period> periods;

  /// 同名课程条数；> 1 才显示「删除所有同名课程」。
  final int sameNameCount;

  /// 当前显示周次；null = 不提供「本周」相关动作。
  final int? currentWeek;

  /// 本周是否已有 override（改时间地点或停课）→ 决定是否给「取消本周调整」。
  final bool hasOverrideThisWeek;

  /// 动作标识（供调用方 switch）。返回 null = 用户取消。
  static const String actionEdit = 'edit';
  static const String actionMove = 'move';
  static const String actionCancelWeek = 'cancel_week';
  static const String actionClearWeek = 'clear_week';
  static const String actionDeleteNamed = 'delete_named';
  static const String actionDelete = 'delete';

  /// 弹出面板，返回动作标识；用户点外部或返回时返回 null。
  static Future<String?> show(
    BuildContext context, {
    required CourseOccurrence occurrence,
    required List<Period> periods,
    required int sameNameCount,
    int? currentWeek,
    bool hasOverrideThisWeek = false,
  }) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return showModalBottomSheet<String>(
      context: context,
      constraints: courseSheetConstraints,
      backgroundColor: colors.surfaceContainerLow,
      shape: courseSheetShape,
      clipBehavior: Clip.antiAlias,
      // 内容可能长于弹窗（横屏手机），开启滚动控制并按屏高 85% 封顶
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: SingleChildScrollView(
          child: CourseActionSheet(
            occurrence: occurrence,
            periods: periods,
            sameNameCount: sameNameCount,
            currentWeek: currentWeek,
            hasOverrideThisWeek: hasOverrideThisWeek,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 「本周停课」：本周参数齐 + 未停课（停课的课再停一次无意义）
    final bool showCancelWeek = currentWeek != null && !occurrence.cancelled;
    // 「取消本周调整」：已有 override（改时间地点/停课）时提供；
    // cancelled 兜底也显示（停课必然有 override，不依赖调用方传参正确）
    final bool showClearWeek =
        currentWeek != null && (hasOverrideThisWeek || occurrence.cancelled);
    final String note = occurrence.course.note.trim();

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetDragHandle(),
          SheetCourseHeader(occurrence: occurrence, periods: periods),
          const SizedBox(height: 10),
          // ── 只读信息 ──
          SheetInfoRow(label: '周次', value: courseWeeksText(occurrence)),
          if (note.isNotEmpty) SheetInfoRow(label: '备注', value: note),
          // ── 改这门课本身 ──
          const SheetDivider(),
          SheetActionRow(
            icon: Icons.edit_outlined,
            title: '编辑',
            subtitle: '修改课名、教师、地点、节次与周次',
            onTap: () => Navigator.of(context).pop(actionEdit),
          ),
          SheetActionRow(
            icon: Icons.open_with,
            title: '移动到…',
            subtitle: '改到其他时段，可选仅本周或所有周',
            onTap: () => Navigator.of(context).pop(actionMove),
          ),
          // ── 只改本周 ──
          if (showCancelWeek || showClearWeek) ...<Widget>[
            const SheetDivider(),
            if (showCancelWeek)
              SheetActionRow(
                icon: Icons.event_busy,
                title: '本周停课',
                subtitle: '只停这一周，其他周照常',
                onTap: () => Navigator.of(context).pop(actionCancelWeek),
              ),
            if (showClearWeek)
              SheetActionRow(
                icon: Icons.restart_alt,
                title: '取消本周调整',
                subtitle: '恢复成课表原本的时间地点',
                onTap: () => Navigator.of(context).pop(actionClearWeek),
              ),
          ],
          // ── 删除：危险操作排最后、单独分组 ──
          const SheetDivider(),
          if (sameNameCount > 1)
            SheetActionRow(
              icon: Icons.delete_sweep_outlined,
              title: '删除所有同名课程',
              subtitle: '共 $sameNameCount 条（教务常把同一门课拆成多条）',
              destructive: true,
              onTap: () => Navigator.of(context).pop(actionDeleteNamed),
            ),
          SheetActionRow(
            icon: Icons.delete_outline,
            title: '删除这一门',
            subtitle: '只删掉当前这条安排',
            destructive: true,
            onTap: () => Navigator.of(context).pop(actionDelete),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
