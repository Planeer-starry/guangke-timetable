import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/widgets/cell_action_sheet.dart';

/// 长按操作面板的 UI 验收：手机（compact）与平板（expanded）两种视口。
///
/// 重点验证两件事：
/// 1. 平板上限宽 480 居中——改造前是全宽抽屉，在平板上拉成一整条；
/// 2. 两种视口都不溢出（Flutter 测试里溢出会抛异常）。
void main() {
  CourseOccurrence occurrence({
    bool cancelled = false,
    String location = '松3-308',
  }) {
    return CourseOccurrence(
      course: Course(
        id: 'c_001',
        name: '大学物理C',
        teacher: '苏祉豪',
        location: location,
        colorValue: 0xFF4278B5,
        dayWeek: 1,
        sectionStart: 5,
        sectionEnd: 6,
        weekMask: 0x3,
        note: '',
      ),
      dayWeek: 1,
      sectionStart: 5,
      sectionEnd: 6,
      location: location,
      cancelled: cancelled,
    );
  }

  /// 设置测试视口（逻辑像素）。
  void setViewport(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> openSheet(
    WidgetTester tester, {
    int sameNameCount = 3,
    bool cancelled = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => CellActionSheet.show(
                  ctx,
                  occurrence: occurrence(cancelled: cancelled),
                  periods: Period.defaults,
                  sameNameCount: sameNameCount,
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
    testWidgets('限宽 480，不铺满整个屏幕宽度', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester);

      final Size size = tester.getSize(find.byType(CellActionSheet));
      expect(size.width, lessThanOrEqualTo(480.0));
      expect(size.width, lessThan(900.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('内容完整：课程上下文 + 四个动作', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      await openSheet(tester);

      // 课程上下文
      expect(find.text('大学物理C'), findsOneWidget);
      expect(find.textContaining('周一 第5-6节'), findsOneWidget);
      expect(find.textContaining('14:40-16:15'), findsOneWidget);
      expect(find.text('松3-308 · 苏祉豪'), findsOneWidget);
      // 四个动作
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('移动到…'), findsOneWidget);
      expect(find.text('删除所有同名课程'), findsOneWidget);
      expect(find.text('删除这一门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('手机视口（411×914dp）', () {
    testWidgets('铺满宽度（< 480 时不限宽）', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);

      final Size size = tester.getSize(find.byType(CellActionSheet));
      expect(size.width, greaterThan(400.0));
      expect(size.width, lessThanOrEqualTo(411.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('内容完整，窄屏不溢出', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester);

      expect(find.text('大学物理C'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('移动'), findsNothing); // 标题是「移动到…」
      expect(find.text('移动到…'), findsOneWidget);
      expect(find.text('删除这一门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('内容随状态变化', () {
    testWidgets('同名课程只有 1 条 → 不显示「删除所有同名课程」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, sameNameCount: 1);

      expect(find.text('删除所有同名课程'), findsNothing);
      expect(find.text('删除这一门'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('同名课程 3 条 → 显示条数说明', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, sameNameCount: 3);

      expect(find.textContaining('共 3 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('本周停课 → 顶部出现「本周停课」徽章', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await openSheet(tester, cancelled: true);

      expect(find.text('本周停课'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('地点与教师都为空 → 不渲染空白的元信息行', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    final CourseOccurrence occ = CourseOccurrence(
                      course: const Course(
                        id: 'c_002',
                        name: '自习',
                        teacher: '',
                        location: '',
                        colorValue: 0xFF4278B5,
                        dayWeek: 1,
                        sectionStart: 5,
                        sectionEnd: 6,
                        weekMask: 0x3,
                      ),
                      dayWeek: 1,
                      sectionStart: 5,
                      sectionEnd: 6,
                      location: '',
                    );
                    CellActionSheet.show(
                      ctx,
                      occurrence: occ,
                      periods: Period.defaults,
                      sameNameCount: 1,
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

      expect(find.text('自习'), findsOneWidget);
      // 时间行仍在（节次与作息都有），但「地点 · 教师」行为空被省略
      expect(find.text(' · '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
