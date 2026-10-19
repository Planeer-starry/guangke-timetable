import 'package:flutter/material.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/undo_stack.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/period_editor.dart';
import 'package:timetable/widgets/app_card.dart';
import 'package:timetable/widgets/time_picker_sheet.dart';

/// 作息设置页（J10）：编辑每节起止时间、增删节次、整体平移、恢复默认。
///
/// 周视图时间列 / 课程编辑页节次下拉 / 小组件行标签都从
/// `TimetableData.periods` 派生，这里改完保存即全局生效。
/// 只允许删**最后一节**：删中间节会让后续 index 移位、课程节次号错位。
class PeriodSettingsScreen extends StatefulWidget {
  const PeriodSettingsScreen({
    super.key,
    required this.data,
    required this.storage,
    required this.undoStack,
  });

  final ValueNotifier<TimetableData> data;
  final StorageService storage;
  final UndoStack undoStack;

  @override
  State<PeriodSettingsScreen> createState() => _PeriodSettingsScreenState();
}

class _PeriodSettingsScreenState extends State<PeriodSettingsScreen> {
  /// 行首「第 N 节」的固定宽度（各行时间 chip 左对齐）。
  static const double _labelWidth = 64;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作息时间'),
        actions: <Widget>[
          PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'shift') {
                _showShiftDialog();
              } else if (value == 'reset') {
                _confirmReset();
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'shift', child: Text('整体平移…')),
                  PopupMenuItem<String>(value: 'reset', child: Text('恢复默认')),
                ],
          ),
        ],
      ),
      body: ValueListenableBuilder<TimetableData>(
        valueListenable: widget.data,
        builder: (BuildContext context, TimetableData data, _) {
          final List<Period> periods = data.periods;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  AppCard(
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.schedule,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          periodsSummary(periods),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < periods.length; i++)
                    _buildRow(
                      context,
                      periods[i],
                      index: i,
                      isLast: i == periods.length - 1,
                      canDelete: periods.length > 1,
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: periods.length >= 24 ? null : _addPeriod,
                    icon: const Icon(Icons.add),
                    label: const Text('添加一节'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 一行：第 N 节 + 开始 / 结束两个时间 chip + 最后一行的删除按钮。
  Widget _buildRow(
    BuildContext context,
    Period period, {
    required int index,
    required bool isLast,
    required bool canDelete,
  }) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _labelWidth,
            child: Text(
              '第 ${period.index} 节',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _timeChip('开始', period.start, () => _editStart(index)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: _timeChip('结束', period.end, () => _editEnd(index)),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 40,
            child: isLast && canDelete
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除最后一节',
                    onPressed: _removeLastPeriod,
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// 「开始 08:30」/「结束 09:15」时间 chip。
  Widget _timeChip(String label, String time, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        '$label $time',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  // ───────────────────────── 编辑单个时间 ─────────────────────────

  Future<void> _editStart(int index) async {
    final Period period = widget.data.value.periods[index];
    final String? picked = await TimePickerSheet.show(
      context,
      title: '第 ${period.index} 节开始时间',
      initial: period.start,
      subtitle: '结束于 ${period.end}',
    );
    if (picked == null || !mounted) {
      return;
    }
    final List<Period> current = widget.data.value.periods;
    if (index >= current.length) {
      return;
    }
    final int? start = minutesOf(picked);
    final int? end = minutesOf(period.end);
    if (start == null || end == null || start >= end) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    final List<Period> next = <Period>[...current];
    next[index] = Period(index: period.index, start: picked, end: period.end);
    await _commit(next);
  }

  Future<void> _editEnd(int index) async {
    final Period period = widget.data.value.periods[index];
    final String? picked = await TimePickerSheet.show(
      context,
      title: '第 ${period.index} 节结束时间',
      initial: period.end,
      subtitle: '开始于 ${period.start}',
    );
    if (picked == null || !mounted) {
      return;
    }
    final List<Period> current = widget.data.value.periods;
    if (index >= current.length) {
      return;
    }
    final int? start = minutesOf(period.start);
    final int? end = minutesOf(picked);
    if (start == null || end == null || start >= end) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
      return;
    }
    final List<Period> next = <Period>[...current];
    next[index] = Period(index: period.index, start: period.start, end: picked);
    await _commit(next);
  }

  // ───────────────────────── 添加 / 删除 ─────────────────────────

  Future<void> _addPeriod() async {
    final List<Period> current = widget.data.value.periods;
    final List<Period> next = addPeriod(current);
    if (next.length == current.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法添加：已达 24 节上限，或当天剩余时间不足')));
      return;
    }
    await _commit(next);
  }

  /// 删除最后一节；有课程引用（sectionStart..sectionEnd 覆盖该节）则拒绝。
  Future<void> _removeLastPeriod() async {
    final TimetableData data = widget.data.value;
    final List<Period> periods = data.periods;
    if (periods.length <= 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少保留一节')));
      return;
    }
    final int lastIndex = periods.last.index;
    final List<Course> using = <Course>[
      for (final Course course in data.courses)
        if (course.sectionStart <= lastIndex && course.sectionEnd >= lastIndex)
          course,
    ];
    if (using.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('有 ${using.length} 门课用到第 $lastIndex 节，请先调整这些课程'),
        ),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('删除第 $lastIndex 节'),
        content: const Text('仅能删除最后一节，确定删除吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _commit(removeLastPeriod(periods));
  }

  // ───────────────────────── 菜单动作 ─────────────────────────

  Future<void> _showShiftDialog() async {
    final int? delta = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => const _ShiftDialog(),
    );
    if (delta == null || !mounted) {
      return;
    }
    if (delta < -120 || delta > 120) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('平移分钟数需在 -120~120 之间')));
      return;
    }
    await _commit(shiftAll(widget.data.value.periods, delta));
  }

  Future<void> _confirmReset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('将恢复为广科默认 10 节作息，确定？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _commit(Period.defaults);
  }

  // ───────────────────────── 统一保存 ─────────────────────────

  /// 改时间 / 添加 / 删除 / 平移 / 恢复默认都走这里：
  /// 校验 -> 落盘 -> 压撤销栈 -> 写回内存 -> 刷新小组件。
  Future<void> _commit(List<Period> periods) async {
    final String? error = validatePeriods(periods);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    final TimetableData before = widget.data.value;
    final TimetableData updated = before.copyWith(periods: periods);
    try {
      await widget.storage.save(updated);
    } catch (saveError) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$saveError')));
      return;
    }
    if (!mounted) {
      return;
    }
    widget.undoStack.push(before);
    widget.data.value = updated;
    // 不能漏：小组件的行标签（节次区间 + 开始时间）由这次刷新同步
    WidgetService.refreshAll(updated);
  }
}

/// 整体平移输入对话框。
///
/// controller 由对话框自己持有并在 dispose 释放（J8 教训）；
/// 输入解析不出整数时确定按钮禁用，pop 的一定是合法 int。
class _ShiftDialog extends StatefulWidget {
  const _ShiftDialog();

  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _parsed => int.tryParse(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('整体平移'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        decoration: const InputDecoration(
          labelText: '平移分钟数',
          hintText: '如 -10 表示全部提前 10 分钟',
          border: OutlineInputBorder(),
        ),
        onChanged: (String value) => setState(() {}),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _parsed == null
              ? null
              : () => Navigator.of(context).pop(_parsed),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
