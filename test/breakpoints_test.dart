import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/utils/breakpoints.dart';

/// 以指定逻辑宽度（dpr=1，物理=逻辑）pump 一个空页面并返回断点结果。
Future<WindowSize> measureWidth(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  late WindowSize result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          result = windowSizeOf(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  testWidgets('599 逻辑宽 → compact', (WidgetTester tester) async {
    expect(await measureWidth(tester, 599), WindowSize.compact);
  });

  testWidgets('600 逻辑宽 → medium（下边界含）', (WidgetTester tester) async {
    expect(await measureWidth(tester, 600), WindowSize.medium);
  });

  testWidgets('839 逻辑宽 → medium（上边界不含）', (WidgetTester tester) async {
    expect(await measureWidth(tester, 839), WindowSize.medium);
  });

  testWidgets('840 逻辑宽 → expanded（下边界含）', (WidgetTester tester) async {
    expect(await measureWidth(tester, 840), WindowSize.expanded);
  });

  testWidgets('1500 逻辑宽（平板横屏）→ expanded', (WidgetTester tester) async {
    expect(await measureWidth(tester, 1500), WindowSize.expanded);
  });
}
