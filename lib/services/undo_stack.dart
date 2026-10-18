import 'package:timetable/models/timetable_data.dart';

/// 撤销栈：编辑 / 删除 / 移动等操作前压入「修改前」的课表快照。
///
/// 深度上限 [maxDepth]（默认 20），防止长编辑会话内存无限增长；
/// 超深时丢弃最旧的记录。导入 / 清空等整体替换操作应调用 [clear]。
class UndoStack {
  UndoStack({this.maxDepth = 20});

  final int maxDepth;
  final List<TimetableData> _stack = <TimetableData>[];

  bool get canUndo => _stack.isNotEmpty;

  /// 压入快照；超过深度上限时丢最旧的。
  void push(TimetableData before) {
    _stack.add(before);
    if (_stack.length > maxDepth) {
      _stack.removeAt(0);
    }
  }

  /// 弹出最近一次快照；栈空返回 null（调用方需判空）。
  TimetableData? pop() {
    if (_stack.isEmpty) {
      return null;
    }
    return _stack.removeLast();
  }

  /// 清空（导入新课表 / 清空课表等整体替换后调用，
  /// 撤销不应跨整体替换生效）。
  void clear() {
    _stack.clear();
  }
}
