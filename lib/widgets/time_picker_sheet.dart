/// 自定义时间选择面板（J10 作息编辑用）。
///
/// 不用 Material 的 showTimePicker：项目未引入 flutter_localizations
/// （与现有 intl 依赖版本冲突装不上），其按钮 / 提示会是英文；
/// 这里用课程面板同款外壳 + 时 / 分双轮盘 + 快捷时间 chips 自己实现。
library;

import 'package:flutter/material.dart';

import 'package:timetable/utils/period_editor.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 时间选择底部面板：时（0-23）/ 分（0-59）两个轮盘。
class TimePickerSheet extends StatefulWidget {
  const TimePickerSheet({
    super.key,
    required this.title,
    required this.initial,
    this.subtitle,
  });

  /// 头卡标题，如「第 1 节开始时间」。
  final String title;

  /// 初始时间 `HH:mm`；解析失败回退 08:00。
  final String initial;

  /// 头卡说明行（如「结束于 09:15」），可空。
  final String? subtitle;

  /// 弹出面板；确定返回 `HH:mm`，取消返回 null。
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String initial,
    String? subtitle,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: courseSheetShape,
      constraints: courseSheetConstraints,
      builder: (_) =>
          TimePickerSheet(title: title, initial: initial, subtitle: subtitle),
    );
  }

  @override
  State<TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<TimePickerSheet> {
  /// 快捷时间（广科作息的关键节点）。
  static const List<String> _quickTimes = <String>[
    '08:00',
    '08:30',
    '10:00',
    '10:25',
    '14:00',
    '14:40',
    '19:00',
    '19:30',
  ];

  /// 轮盘行高。
  static const double _itemExtent = 44;

  /// 轮盘可视高度（约 4 行）。
  static const double _wheelHeight = 180;

  /// 轮子中间值由这两个 controller 承载（dispose 释放，J8 教训）。
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final int minutes = minutesOf(widget.initial) ?? 8 * 60;
    _hourController = FixedExtentScrollController(initialItem: minutes ~/ 60);
    _minuteController = FixedExtentScrollController(initialItem: minutes % 60);
  }

  @override
  void dispose() {
    _minuteController.dispose();
    _hourController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SheetDragHandle(),
          SheetHeaderCard(
            color: theme.colorScheme.primary,
            title: widget.title,
            lines: <String>[if (widget.subtitle != null) widget.subtitle!],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(child: _buildWheel(_hourController, 24)),
              Text(':', style: theme.textTheme.titleLarge),
              Expanded(child: _buildWheel(_minuteController, 60)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: <Widget>[
                for (final String time in _quickTimes)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(time),
                      onPressed: () => _setTime(time),
                    ),
                  ),
              ],
            ),
          ),
          const SheetDivider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _confirm, child: const Text('确定')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 时 / 分轮盘：固定高度 + 中间选中行的上下参考线。
  Widget _buildWheel(FixedExtentScrollController controller, int count) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: _wheelHeight,
      child: Stack(
        children: <Widget>[
          // 中间选区的上下参考线（纯视觉，不拦截手势）
          Positioned(
            left: 16,
            right: 16,
            top: (_wheelHeight - _itemExtent) / 2,
            child: IgnorePointer(
              child: Container(
                height: _itemExtent,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
          ),
          ListWheelScrollView(
            controller: controller,
            itemExtent: _itemExtent,
            physics: const FixedExtentScrollPhysics(),
            children: <Widget>[
              for (int i = 0; i < count; i++)
                Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 快捷时间：把两个轮子直接设到目标时刻。
  void _setTime(String time) {
    final int? minutes = minutesOf(time);
    if (minutes == null) {
      return;
    }
    _hourController.jumpToItem(minutes ~/ 60);
    _minuteController.jumpToItem(minutes % 60);
  }

  void _confirm() {
    Navigator.of(context).pop(
      hhmmOf(
        _hourController.selectedItem * 60 + _minuteController.selectedItem,
      ),
    );
  }
}
