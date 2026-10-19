import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 单击课块弹出的课程详情面板。
///
/// 与长按的 [CellActionSheet] 共用 `course_sheet_parts.dart` 的外壳与零件：
/// 同一个课程上下文卡片、同一种动作行、同样的限宽 480 与 28dp 圆角。
///
/// 区别只在密度：长按面板只给操作，单击面板先展示信息（周次 / 备注）
/// 再给操作，且多了「本周停课 / 取消本周调整」这两个周级动作。
///
/// 动作回调的约定：**先关弹窗再调用回调**，避免编辑页 / 删除确认框
/// 被本弹窗遮住。
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
  // 「本周停课」：本周参数齐 + 未停课（停课的课再停一次无意义）
  final bool showCancelThisWeek =
      currentWeek != null && !occurrence.cancelled && onCancelThisWeek != null;
  // 「取消本周调整」：已有 override（改时间地点/停课）时提供；
  // cancelled 兜底也显示（停课必然有 override，不依赖调用方传参正确）
  final bool showClearWeekAdjust =
      currentWeek != null &&
      onClearWeekAdjust != null &&
      (hasOverrideThisWeek || occurrence.cancelled);

  final String weeksText = courseWeeksText(occurrence);
  final String note = occurrence.course.note.trim();

  return showModalBottomSheet<void>(
    context: context,
    constraints: courseSheetConstraints,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: courseSheetShape,
    clipBehavior: Clip.antiAlias,
    builder: (BuildContext sheetContext) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetDragHandle(),
          SheetCourseHeader(occurrence: occurrence, periods: periods),
          const SizedBox(height: 10),
          // 只读信息：时间/地点/教师已在上面卡片里，这里补周次与备注
          SheetInfoRow(label: '周次', value: weeksText),
          if (note.isNotEmpty) SheetInfoRow(label: '备注', value: note),
          // 周级调整 + 编辑：同一组（都是"改这门课本周的样子"）
          if (showCancelThisWeek ||
              showClearWeekAdjust ||
              onEdit != null) ...<Widget>[
            const SizedBox(height: 6),
            const SheetDivider(),
            if (onEdit != null)
              SheetActionRow(
                icon: Icons.edit_outlined,
                title: '编辑',
                subtitle: '修改课名、教师、地点、节次与周次',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onEdit();
                },
              ),
            if (showCancelThisWeek)
              SheetActionRow(
                icon: Icons.event_busy,
                title: '本周停课',
                subtitle: '只停这一周，其他周照常',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onCancelThisWeek();
                },
              ),
            if (showClearWeekAdjust)
              SheetActionRow(
                icon: Icons.restart_alt,
                title: '取消本周调整',
                subtitle: '恢复成课表原本的时间地点',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onClearWeekAdjust();
                },
              ),
          ],
          // 删除：单独一组
          if (onDelete != null) ...<Widget>[
            const SheetDivider(),
            SheetActionRow(
              icon: Icons.delete_outline,
              title: '删除这一门',
              subtitle: '只删掉当前这条安排',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onDelete();
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
