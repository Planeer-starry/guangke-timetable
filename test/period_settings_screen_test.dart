import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/period_settings_screen.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/undo_stack.dart';

/// 作息设置页（J10）widget 验收：行数 / 删除守卫 / 添加 / 恢复默认 / 编辑。

/// save 落盘替换为空实现：testWidgets 跑在 fake async zone，
/// 真实文件 I/O 的 Future 永远不会完成（settings_tablet_test 踩过的坑），
/// 而本页每个操作都会 save。目录参数不会被触达。
class _NoopStorage extends StorageService {
  _NoopStorage() : super(directory: Directory('no-io'));

  @override
  Future<void> save(TimetableData data) async {}
}

/// 默认作息（10 节）+ 可选课程列表的课表。
TimetableData _data({List<Course> courses = const <Course>[]}) {
  return TimetableData.empty().copyWith(courses: courses);
}

/// 一门用到第 9~10 节的课（删除第 10 节的守卫用例）。
const Course _courseUsingLastPeriod = Course(
  id: 'c_001',
  name: '计算机网络',
  teacher: '张三',
  location: 'A101',
  colorValue: 0xFF3F51B5,
  dayWeek: 1,
  sectionStart: 9,
  sectionEnd: 10,
  weekMask: 65535,
);

Future<void> pumpScreen(
  WidgetTester tester,
  ValueNotifier<TimetableData> data,
) async {
  // 视口调高：默认 800x600 下 10 行作息刚好把底部「添加一节」挤出视口，
  // ListView 懒构建 -> find 找不到它（踩过）。给足高度省掉滚动。
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PeriodSettingsScreen(
        data: data,
        storage: _NoopStorage(),
        undoStack: UndoStack(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('列表行数 = periods 长度，且只有最后一行有删除按钮', (WidgetTester tester) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    expect(find.text('第 1 节'), findsOneWidget);
    expect(find.text('第 10 节'), findsOneWidget);
    // 10 行 × (开始 + 结束) 两个时间 chip
    expect(find.byType(OutlinedButton), findsNWidgets(20));
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text('10 节 · 08:30–21:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点「添加一节」-> periods 长度 +1', (WidgetTester tester) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    await tester.tap(find.text('添加一节'));
    await tester.pumpAndSettle();

    expect(data.value.periods.length, 11);
    expect(find.text('第 11 节'), findsOneWidget);
  });

  testWidgets('删除最后一节（无课程引用）-> 长度 -1', (WidgetTester tester) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(data.value.periods.length, 9);
    expect(find.text('第 10 节'), findsNothing);
  });

  testWidgets('删除被课程引用的最后一节 -> 长度不变 + SnackBar', (WidgetTester tester) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(courses: const <Course>[_courseUsingLastPeriod]),
    );
    await pumpScreen(tester, data);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(data.value.periods.length, 10);
    expect(find.text('有 1 门课用到第 10 节，请先调整这些课程'), findsOneWidget);
  });

  testWidgets('「恢复默认」-> periods 回到 Period.defaults', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    // 先改乱（添加一节）
    await tester.tap(find.text('添加一节'));
    await tester.pumpAndSettle();
    expect(data.value.periods.length, 11);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(data.value.periods.length, Period.defaults.length);
    for (int i = 0; i < Period.defaults.length; i++) {
      expect(data.value.periods[i].start, Period.defaults[i].start);
      expect(data.value.periods[i].end, Period.defaults[i].end);
    }
  });

  testWidgets('改第 1 节开始时间 -> data.periods[0].start 变化', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    await tester.tap(find.text('开始 08:30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(data.value.periods[0].start, '08:00');
    expect(data.value.periods[0].end, '09:15');
  });

  testWidgets('开始时间晚于结束时间 -> SnackBar 且不提交', (WidgetTester tester) async {
    final ValueNotifier<TimetableData> data = ValueNotifier<TimetableData>(
      _data(),
    );
    await pumpScreen(tester, data);

    // 第 1 节 08:30-09:15，把开始改成 10:00（> 09:15）
    await tester.tap(find.text('开始 08:30'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(data.value.periods[0].start, '08:30');
    expect(find.text('结束时间必须晚于开始时间'), findsOneWidget);
  });
}
