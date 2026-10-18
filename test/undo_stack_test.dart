import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/undo_stack.dart';

TimetableData dataOf(String mark) {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': mark,
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': <Map<String, dynamic>>[],
    'overrides': <Map<String, dynamic>>[],
  });
}

void main() {
  test('空栈 canUndo == false', () {
    final UndoStack stack = UndoStack();
    expect(stack.canUndo, false);
  });

  test('push 后 canUndo == true，pop 返回最后压入的', () {
    final UndoStack stack = UndoStack();
    stack.push(dataOf('A'));
    stack.push(dataOf('B'));
    expect(stack.canUndo, true);

    final TimetableData? popped = stack.pop();
    expect(popped, isNotNull);
    expect(popped!.meta.semesterName, 'B');
  });

  test('pop 到空后再次 pop 返回 null', () {
    final UndoStack stack = UndoStack();
    stack.push(dataOf('A'));
    stack.pop();
    expect(stack.pop(), isNull);
    expect(stack.canUndo, false);
  });

  test('maxDepth 3 时 push 4 个，最旧的被挤出', () {
    final UndoStack stack = UndoStack(maxDepth: 3);
    stack.push(dataOf('A'));
    stack.push(dataOf('B'));
    stack.push(dataOf('C'));
    stack.push(dataOf('D'));

    // 栈里只剩 B C D：连续 pop 三次拿到 D、C、B，A 已被丢弃
    final List<String?> marks = <String?>[
      stack.pop()?.meta.semesterName,
      stack.pop()?.meta.semesterName,
      stack.pop()?.meta.semesterName,
    ];
    expect(marks, <String?>['D', 'C', 'B']);
    expect(stack.canUndo, false);
  });

  test('clear 后 canUndo == false', () {
    final UndoStack stack = UndoStack();
    stack.push(dataOf('A'));
    stack.push(dataOf('B'));
    stack.clear();
    expect(stack.canUndo, false);
    expect(stack.pop(), isNull);
  });
}