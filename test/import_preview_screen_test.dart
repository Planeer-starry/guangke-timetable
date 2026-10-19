import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/screens/import_preview_screen.dart';

/// J11 预览页验收：JSON 携带学期 / 作息的「将同时设置」块、
/// App 备份副文案、学期覆盖警告、确认 pop 带回 meta / periods / overrides。

Course _course() => Course(
  id: 'c_001',
  name: '计算机网络',
  teacher: '张三',
  location: '教学楼A101',
  colorValue: 0xFF5A68B0,
  dayWeek: 1,
  sectionStart: 3,
  sectionEnd: 4,
  weekMask: 0xFFFF,
  note: '',
);

TimetableMeta _importedMeta() => TimetableMeta(
  school: '广东科技学院',
  semesterName: '2026-2027年第1学期',
  week1Monday: DateTime(2026, 9, 7),
  totalWeeks: 20,
);

TimetableMeta _unsetMeta() => TimetableMeta(
  school: '广东科技学院',
  semesterName: '',
  week1Monday: TimetableData.unsetWeek1Monday,
  totalWeeks: 20,
);

const List<Period> _importedPeriods = <Period>[
  Period(index: 1, start: '08:30', end: '09:15'),
  Period(index: 2, start: '09:20', end: '10:05'),
];

void main() {
  testWidgets('importedMeta + importedPeriods → 显示「将同时设置」块', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
          importedMeta: _importedMeta(),
          importedPeriods: _importedPeriods,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('将同时设置'), findsOneWidget);
    expect(find.textContaining('第一周：2026-09-07'), findsOneWidget);
    expect(find.textContaining('共 20 周'), findsOneWidget);
    expect(find.textContaining('学期：2026-2027年第1学期'), findsOneWidget);
    expect(find.textContaining('作息：2 节'), findsOneWidget);
  });

  testWidgets('不传 importedMeta / periods → 整块不显示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('将同时设置'), findsNothing);
    expect(find.textContaining('第一周'), findsNothing);
    expect(find.textContaining('作息：'), findsNothing);
  });

  testWidgets('isFullBackup → 显示完整恢复副文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
          isFullBackup: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('简课表的备份文件'), findsOneWidget);
    expect(find.textContaining('完整恢复学期、作息'), findsOneWidget);
    expect(find.textContaining('停课 / 移动调整'), findsOneWidget);
  });

  testWidgets('isFullBackup = false → 不显示备份副文案', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('简课表的备份文件'), findsNothing);
  });

  testWidgets('currentMeta 已配置且不同 → 显示「将覆盖当前学期设置（原：…）」', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
          currentMeta: TimetableMeta(
            school: '广东科技学院',
            semesterName: '旧学期',
            week1Monday: DateTime(2026, 9, 14),
            totalWeeks: 20,
          ),
          importedMeta: _importedMeta(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('将覆盖当前学期设置'), findsOneWidget);
    expect(find.textContaining('原：2026-09-14'), findsOneWidget);
  });

  testWidgets('currentMeta 未配置 → 不显示覆盖警告，确认按钮可用', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: <Course>[_course()],
          skippedCount: 0,
          currentMeta: _unsetMeta(),
          importedMeta: _importedMeta(),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('将覆盖当前学期设置'), findsNothing);
    final FilledButton button = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('确认导入 → pop 带回 meta / periods / overrides', (
    WidgetTester tester,
  ) async {
    ImportConfirmation? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              popped = await Navigator.of(context).push<ImportConfirmation>(
                MaterialPageRoute<ImportConfirmation>(
                  builder: (_) => ImportPreviewScreen(
                    courses: <Course>[_course()],
                    skippedCount: 0,
                    importedMeta: _importedMeta(),
                    importedPeriods: _importedPeriods,
                    importedOverrides: const <CourseOverride>[
                      CourseOverride(
                        courseId: 'c_001',
                        week: 8,
                        dayWeek: 3,
                        sectionStart: 5,
                        sectionEnd: 6,
                        location: '实验楼B203',
                      ),
                    ],
                    isFullBackup: true,
                  ),
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.courses, isNotEmpty);
    expect(popped!.week1Monday, DateTime(2026, 9, 7));
    expect(popped!.totalWeeks, 20);
    expect(popped!.semesterName, '2026-2027年第1学期');
    expect(popped!.periods, isNotNull);
    expect(popped!.periods!.length, 2);
    expect(popped!.overrides, isNotNull);
    expect(popped!.overrides!.single.courseId, 'c_001');
    expect(popped!.overrides!.single.location, '实验楼B203');
  });
}
