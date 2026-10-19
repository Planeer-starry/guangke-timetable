import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/widgets/time_picker_sheet.dart';

/// 时间选择面板（J10）：初始回落 / 快捷 chip / 取消 / 双视口。
void main() {
  /// pump 出宿主页并点「打开」弹出面板；
  /// 面板关闭后的返回值会 append 进 [results]。
  Future<void> pumpAndOpen(
    WidgetTester tester,
    List<String?> results, {
    String initial = '08:30',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final String? value = await TimePickerSheet.show(
                    ctx,
                    title: '第 1 节开始时间',
                    initial: initial,
                  );
                  results.add(value);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('初始值 08:30 回落到时轮 8、分轮 30', (WidgetTester tester) async {
    await pumpAndOpen(tester, <String?>[], initial: '08:30');

    final ListWheelScrollView hourWheel = tester.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView).at(0),
    );
    expect((hourWheel.controller! as FixedExtentScrollController).selectedItem, 8);
    final ListWheelScrollView minuteWheel = tester.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView).at(1),
    );
    expect((minuteWheel.controller! as FixedExtentScrollController).selectedItem, 30);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始值非法时回退 08:00', (WidgetTester tester) async {
    await pumpAndOpen(tester, <String?>[], initial: '9:5');

    final ListWheelScrollView hourWheel = tester.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView).at(0),
    );
    expect((hourWheel.controller! as FixedExtentScrollController).selectedItem, 8);
    final ListWheelScrollView minuteWheel = tester.widget<ListWheelScrollView>(
      find.byType(ListWheelScrollView).at(1),
    );
    expect((minuteWheel.controller! as FixedExtentScrollController).selectedItem, 0);
  });

  testWidgets('点快捷 chip 08:00 -> 确定返回 08:00', (WidgetTester tester) async {
    final List<String?> results = <String?>[];
    await pumpAndOpen(tester, results, initial: '09:15');

    await tester.tap(find.text('08:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(results, <String?>['08:00']);
  });

  testWidgets('点取消返回 null', (WidgetTester tester) async {
    final List<String?> results = <String?>[];
    await pumpAndOpen(tester, results, initial: '09:15');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(results, <String?>[null]);
  });

  testWidgets('平板视口（900×1200）内容限宽 480', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200) * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await pumpAndOpen(tester, <String?>[], initial: '08:30');

    final Size size = tester.getSize(find.byType(TimePickerSheet));
    expect(size.width, lessThanOrEqualTo(480.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机视口（411×914）铺满且不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 914) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await pumpAndOpen(tester, <String?>[], initial: '08:30');

    final Size size = tester.getSize(find.byType(TimePickerSheet));
    expect(size.width, greaterThan(400.0));
    expect(size.width, lessThanOrEqualTo(411.0));
    // 轮子 / 快捷 chip / 按钮都在
    expect(find.byType(ListWheelScrollView), findsNWidgets(2));
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
