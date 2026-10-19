import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_action_sheet.dart';

/// 统一后的课程操作面板（单击与长按共用）验收。
///
/// 重点：合并前「移动到…」只在长按、「本周停课」只在单击，用户得记手势；
/// 合并后同一个面板包含全部动作，测试要保证这个「全集」不再分裂。
void main() {
  CourseOccurrence occurrence({
    bool cancelled = false,
    String note = '',
    String location = '松3-308',
    String teacher = '苏祉豪',
  }) {
    return CourseOccurrence(
      course: Course(
        id: 'c_001',
        name: '大学物理C',
        teacher: teacher,
        location: location,
        colorValue: 0xFF4278B5,
        dayWeek: 1,
        sectionStart: 5,
        sectionEnd: 6,
        weekMask: 0x3,
        note: note,
      ),
      dayWeek: 1,
      sectionStart: 5,
      sectionEnd: 6,
      location: location,
      cancelled: cancelled,
    );
  }

  void setViewport(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> openSheet(
    WidgetTester tester, {
    CourseOccurrence? occ,
    int sameNameCount = 3,
    int? currentWeek = 8,
    bool hasOverrideThisWeek = false,
  }) async {
    final CourseOccurrence target = occ ?? occurrence();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => CourseActionSheet.show(
                  ctx,
                  occurrence: target,
                  periods: Period.defaults,
                  sameNameCount: sameNameCount,
                  currentWeek: currentWeek,
                  hasOverrideThisWeek: hasOverrideThisWeek,
                ),
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

  group('统一性：一个面板包含全部动作', () {
    testWidgets('单击/长按共用的面板含六个动作（不再分裂）', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester);

      // 原来只在长按面板
      expect(find.text('移动到…'), findsOneWidget);
      expect(find.text('删除所有同名课程'), findsOneWidget);
      // 原来只在单击面板
      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除这一门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('动作顺序按危险度递增：修改 → 本周 → 删除', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester);

      double topOf(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(topOf('编辑'), lessThan(topOf('移动到…')));
      expect(topOf('移动到…'), lessThan(topOf('本周停课')));
      expect(topOf('本周停课'), lessThan(topOf('删除所有同名课程')));
      expect(topOf('删除所有同名课程'), lessThan(topOf('删除这一门')));
    });
  });

  group('平板视口（900×1200dp）', () {
    testWidgets('限宽 480，不铺满', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester);

      final Size size = tester.getSize(find.byType(CourseActionSheet));
      expect(size.width, lessThanOrEqualTo(480.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('手机视口（411×914dp）', () {
    testWidgets('铺满宽度且内容完整', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);

      final Size size = tester.getSize(find.byType(CourseActionSheet));
      expect(size.width, greaterThan(400.0));
      expect(size.width, lessThanOrEqualTo(411.0));
      // 课程上下文
      expect(find.text('大学物理C'), findsOneWidget);
      expect(find.textContaining('周一 第5-6节'), findsOneWidget);
      expect(find.text('松3-308 · 苏祉豪'), findsOneWidget);
      expect(find.text('周次'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('横屏矮屏不溢出（内部可滚动）', (WidgetTester tester) async {
      // 914×411 横屏：6 个动作放不下，靠 SingleChildScrollView 兜底
      setViewport(tester, const Size(914, 411), 2.0);
      await openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('编辑'), findsOneWidget);
    });
  });

  group('条件显示的动作为', () {
    testWidgets('同名只有 1 条 → 无「删除所有同名课程」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, sameNameCount: 1);

      expect(find.text('删除所有同名课程'), findsNothing);
      expect(find.text('删除这一门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('同名 3 条 → 显示条数说明', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, sameNameCount: 3);

      expect(find.textContaining('共 3 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无本周参数 → 不显示任何周级动作', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, currentWeek: null);

      expect(find.text('本周停课'), findsNothing);
      expect(find.text('取消本周调整'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未停课 → 显示「本周停课」，无「取消本周调整」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);

      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('取消本周调整'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已停课 → 徽章 + 只有「取消本周调整」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(
        tester,
        occ: occurrence(cancelled: true),
        hasOverrideThisWeek: true,
      );

      // 卡片里的徽章
      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('取消本周调整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有 override 且未停课 → 两个周级动作都显示', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, hasOverrideThisWeek: true);

      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('取消本周调整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('备注为空不渲染 / 非空渲染', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);
      expect(find.text('备注'), findsNothing);

      await tester.tapAt(const Offset(400, 50)); // 点遮罩关闭
      await tester.pumpAndSettle();

      await openSheet(tester, occ: occurrence(note: '带计算器'));
      expect(find.text('备注'), findsOneWidget);
      expect(find.text('带计算器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('返回值约定', () {
    testWidgets('点「移动到…」→ 返回 actionMove', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      String? result;
      final CourseOccurrence target = occurrence();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await CourseActionSheet.show(
                      ctx,
                      occurrence: target,
                      periods: Period.defaults,
                      sameNameCount: 1,
                      currentWeek: 8,
                    );
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

      await tester.tap(find.text('移动到…'));
      await tester.pumpAndSettle();

      expect(result, CourseActionSheet.actionMove);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点「本周停课」→ 返回 actionCancelWeek', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      String? result;
      final CourseOccurrence target = occurrence();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await CourseActionSheet.show(
                      ctx,
                      occurrence: target,
                      periods: Period.defaults,
                      sameNameCount: 1,
                      currentWeek: 8,
                    );
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

      await tester.tap(find.text('本周停课'));
      await tester.pumpAndSettle();

      expect(result, CourseActionSheet.actionCancelWeek);
      expect(tester.takeException(), isNull);
    });
  });
}
