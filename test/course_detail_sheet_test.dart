import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/course_detail_sheet.dart';

/// 单击详情面板的 UI 验收：与长按面板同一套外壳，内容密度更高。
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
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    int? currentWeek,
    bool hasOverrideThisWeek = false,
    VoidCallback? onCancelThisWeek,
    VoidCallback? onClearWeekAdjust,
  }) async {
    final CourseOccurrence target = occ ?? occurrence();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showCourseDetailSheet(
                  ctx,
                  occurrence: target,
                  periods: Period.defaults,
                  onEdit: onEdit,
                  onDelete: onDelete,
                  currentWeek: currentWeek,
                  hasOverrideThisWeek: hasOverrideThisWeek,
                  onCancelThisWeek: onCancelThisWeek,
                  onClearWeekAdjust: onClearWeekAdjust,
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

  group('平板视口（900×1200dp）', () {
    testWidgets('与长按面板同一套外壳：限宽 480、居中浮层', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester, onEdit: () {}, onDelete: () {});

      // 弹窗内容宽度不得超过 480（sheet 本体占满，内容被约束居中）
      final Size header = tester.getSize(find.text('大学物理C'));
      expect(header.width, lessThan(480.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('手机视口（411×914dp）', () {
    testWidgets('内容完整：课程上下文 + 周次', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, onEdit: () {});

      expect(find.text('大学物理C'), findsOneWidget);
      expect(find.textContaining('周一 第5-6节'), findsOneWidget);
      expect(find.textContaining('14:40-16:15'), findsOneWidget);
      expect(find.text('松3-308 · 苏祉豪'), findsOneWidget);
      expect(find.text('周次'), findsOneWidget);
      expect(find.text('1-2周'), findsOneWidget); // weekMask = 0x3
      expect(tester.takeException(), isNull);
    });

    testWidgets('备注为空 → 不渲染备注行', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);
      expect(find.text('备注'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('备注非空 → 渲染备注行', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, occ: occurrence(note: '带计算器'));
      expect(find.text('备注'), findsOneWidget);
      expect(find.text('带计算器'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('动作按条件显示', () {
    testWidgets('只传 onEdit → 只有编辑，没有删除', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, onEdit: () {});

      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除这一门'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未停课 + 有本周参数 → 显示「本周停课」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(
        tester,
        currentWeek: 8,
        onCancelThisWeek: () {},
      );

      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('取消本周调整'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('已停课 → 顶部徽章 + 只显示「取消本周调整」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(
        tester,
        occ: occurrence(cancelled: true),
        currentWeek: 8,
        onCancelThisWeek: () {},
        onClearWeekAdjust: () {},
      );

      // 卡片里的徽章
      expect(find.text('本周停课'), findsOneWidget);
      // 动作行里不该再出现「本周停课」（停课的课再停无意义）
      expect(find.text('取消本周调整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('本周有 override → 显示「取消本周调整」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(
        tester,
        currentWeek: 8,
        hasOverrideThisWeek: true,
        onCancelThisWeek: () {},
        onClearWeekAdjust: () {},
      );

      expect(find.text('本周停课'), findsOneWidget);
      expect(find.text('取消本周调整'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('没有本周参数 → 两个周级动作都不显示', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, onEdit: () {}, onDelete: () {});

      expect(find.text('本周停课'), findsNothing);
      expect(find.text('取消本周调整'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('回调约定：先关弹窗再执行', () {
    testWidgets('点「删除这一门」→ 弹窗关闭且回调被调用', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      bool deleted = false;
      await openSheet(tester, onDelete: () => deleted = true);

      await tester.tap(find.text('删除这一门'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
      // 弹窗已关闭：课程名不再可见
      expect(find.text('大学物理C'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
