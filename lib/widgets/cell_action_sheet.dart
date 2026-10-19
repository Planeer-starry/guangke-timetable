import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 长按课块呼出的操作面板（只管操作，不展示详情）。
///
/// 与单击弹出的 [showCourseDetailSheet] 共用
/// `course_sheet_parts.dart` 的外壳与零件——两者是同一交互家族的
/// 两种密度，视觉必须一致。
///
/// 设计要点：
/// 1. **限宽 480**：手机上接近全宽，平板上自动居中成浮层卡片；
/// 2. **带课程上下文**：长按只是手段，用户要确认的是「我在操作哪门课」；
/// 3. **危险操作分组**：删除类用 error 色并用分隔线隔开，降低误触。
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
      constraints: courseSheetConstraints,
      backgroundColor: colors.surfaceContainerLow,
      shape: courseSheetShape,
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
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SheetDragHandle(),
          SheetCourseHeader(occurrence: occurrence, periods: periods),
          const SizedBox(height: 8),
          SheetActionRow(
            icon: Icons.edit_outlined,
            title: '编辑',
            subtitle: '修改课名、教师、地点、节次与周次',
            onTap: () => Navigator.of(context).pop('edit'),
          ),
          SheetActionRow(
            icon: Icons.open_with,
            title: '移动到…',
            subtitle: '改到其他时段，可选仅本周或所有周',
            onTap: () => Navigator.of(context).pop('move'),
          ),
          const SheetDivider(),
          if (sameNameCount > 1)
            SheetActionRow(
              icon: Icons.delete_sweep_outlined,
              title: '删除所有同名课程',
              subtitle: '共 $sameNameCount 条（教务常把同一门课拆成多条）',
              destructive: true,
              onTap: () => Navigator.of(context).pop('delete_named'),
            ),
          SheetActionRow(
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
