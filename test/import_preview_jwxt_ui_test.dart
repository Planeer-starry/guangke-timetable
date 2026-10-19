import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/screens/import_preview_screen.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';

/// J5 批 3 的预览页 UI 验收：
/// 作息行两种形态（识别自表格 / 沿用默认）+ fallback 警示行。
///
/// 真机导入要过系统文件选择器，不好自动化；用 widget 测试锁死这几块文案。
void main() {
  Course sampleCourse() => Course(
    id: 'c1',
    name: '高等数学BⅠ',
    teacher: '谌凤霞',
    location: '松6-502',
    colorValue: 0xFFC05B5B,
    dayWeek: 2,
    sectionStart: 7,
    sectionEnd: 8,
    weekMask: 0x3,
    note: '',
  );

  Future<void> pumpPreview(
    WidgetTester tester, {
    required JwxtImportResult jwxt,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImportPreviewScreen(
          courses: jwxt.courses,
          skippedCount: jwxt.skippedCount,
          jwxt: jwxt,
        ),
      ),
    );
    // 预览页是 StatelessWidget，两帧足够
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('预览页 · 作息行', () {
    testWidgets('识别到时间 → 显示「识别自表格」+ 节次数 + 时间', (WidgetTester tester) async {
      await pumpPreview(
        tester,
        jwxt: JwxtImportResult(
          courses: <Course>[sampleCourse()],
          skippedCount: 0,
          week1Monday: DateTime(2026, 8, 31),
          totalWeeks: 20,
          semesterName: '2026-2027年第1学期',
          periods: const <Period>[
            Period(index: 1, start: '08:00', end: '08:45'),
            Period(index: 2, start: '08:55', end: '09:40'),
          ],
          usedDefaultPeriods: false,
          detectedSectionCount: 2,
        ),
      );

      expect(find.textContaining('识别自表格'), findsOneWidget);
      expect(find.textContaining('08:00'), findsOneWidget);
      // 不应出现「沿用默认」
      expect(find.textContaining('沿用默认'), findsNothing);
    });

    testWidgets('没识别到作息 → 显示「沿用默认 10 节」', (WidgetTester tester) async {
      await pumpPreview(
        tester,
        jwxt: JwxtImportResult(
          courses: <Course>[sampleCourse()],
          skippedCount: 0,
          week1Monday: DateTime(2026, 8, 31),
          totalWeeks: 20,
          periods: null,
          usedDefaultPeriods: true,
        ),
      );

      expect(find.textContaining('沿用默认'), findsOneWidget);
      expect(find.textContaining('识别自表格'), findsNothing);
    });
  });

  group('预览页 · fallback 警示', () {
    testWidgets('fallbackCount > 0 → 出现警告文案与图标', (WidgetTester tester) async {
      await pumpPreview(
        tester,
        jwxt: const JwxtImportResult(
          courses: <Course>[],
          skippedCount: 0,
          fallbackCount: 3,
        ),
      );

      expect(find.textContaining('3 条课程只识别出名称'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('fallbackCount == 0 → 不出现警告', (WidgetTester tester) async {
      await pumpPreview(
        tester,
        jwxt: JwxtImportResult(
          courses: <Course>[sampleCourse()],
          skippedCount: 0,
          fallbackCount: 0,
        ),
      );

      expect(find.textContaining('只识别出名称'), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });
}
