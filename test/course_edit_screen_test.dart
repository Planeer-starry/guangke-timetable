import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/course_edit_screen.dart';

/// 「学期已配置」的最小课表。
TimetableData _data() {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': <Map<String, dynamic>>[],
    'overrides': <Map<String, dynamic>>[],
  });
}

/// pump 宿主页并 push 编辑页。[onPopped] 在编辑页 pop 后收到返回值。
/// 编辑页本身不碰 storage（无文件 I/O），无需 runAsync。
Future<void> pumpEditScreen(
  WidgetTester tester,
  TimetableData data,
  void Function(TimetableData?) onPopped,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final TimetableData? result = await Navigator.of(context)
                    .push<TimetableData>(
                      MaterialPageRoute<TimetableData>(
                        builder: (_) =>
                            CourseEditScreen(data: data, course: null),
                      ),
                    );
                onPopped(result);
              },
              child: const Text('打开编辑页'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑页'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('名称为空点保存 → 停在页面并提示', (WidgetTester tester) async {
    await pumpEditScreen(tester, _data(), (_) {});

    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请填写课程名'), findsOneWidget);
    // 仍在编辑页（宿主页按钮不可见）
    expect(find.text('打开编辑页'), findsNothing);
    expect(find.text('新增课程'), findsOneWidget);
  });

  testWidgets('周次清空点保存 → 停在页面', (WidgetTester tester) async {
    await pumpEditScreen(tester, _data(), (_) {});

    // 填上课程名（否则先卡名称校验），再清空周次
    await tester.enterText(find.byType(TextFormField).first, '高等数学');
    await tester.tap(find.text('清空'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(find.text('请至少选择一个周次'), findsOneWidget);
    expect(find.text('打开编辑页'), findsNothing);
  });

  testWidgets('正常填写点保存 → 返回包含该课的 TimetableData', (WidgetTester tester) async {
    TimetableData? result;
    await pumpEditScreen(
      tester,
      _data(),
      (TimetableData? popped) => result = popped,
    );

    await tester.enterText(find.byType(TextFormField).first, '高等数学');
    await tester.enterText(find.byType(TextFormField).last, '教学楼B101');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 编辑页已 pop，回到宿主页
    expect(find.text('打开编辑页'), findsOneWidget);
    expect(result, isNotNull);
    expect(result!.courses.length, 1);
    expect(result!.courses.single.name, '高等数学');
    expect(result!.courses.single.location, '教学楼B101');
    // 新增课 defaultWeek 为 null → 20 周全选
    expect(result!.courses.single.weekMask, 0xFFFFF);
    // 手动课 id 用 u_ 前缀
    expect(result!.courses.single.id, 'u_001');
  });
}
