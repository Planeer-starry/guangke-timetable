import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/home_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/theme_service.dart';

/// 构造「学期已配置」的课表数据。
///
/// [weeksAgo] 表示第一周周一在几周前：0 = 本周一就是第一周周一
/// （今天是第 1 周），6 = 今天是第 7 周。
///
/// 为什么相对 `DateTime.now()` 动态算：HomeScreen 内部用
/// `DateTime.now()` 计算当前周（无法注入），测试必须跟着实时日期走，
/// 否则不同日子跑结果不同。
TimetableData buildData({required int weeksAgo, int totalWeeks = 20}) {
  final DateTime now = DateTime.now();
  final DateTime thisMonday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final DateTime week1Monday = thisMonday.subtract(
    Duration(days: 7 * weeksAgo),
  );
  String two(int n) => n.toString().padLeft(2, '0');
  final String week1 =
      '${week1Monday.year}-${two(week1Monday.month)}-${two(week1Monday.day)}';
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': week1,
      'totalWeeks': totalWeeks,
    },
    'courses': <Map<String, dynamic>>[],
    'overrides': <Map<String, dynamic>>[],
  });
}

/// 有限的 pump 循环，替代 pumpAndSettle。
///
/// ⚠️ BouncingScrollPhysics 的弹道/回弹动画在 widget 测试环境下会让
/// pumpAndSettle() 永不收敛（一直有新帧被调度），导致测试挂死。
/// 这里手动推进 1.2 秒虚拟时间，足够覆盖 250ms 的 animateToPage + 回弹。
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// pump 出完整的 HomeScreen。
///
/// mock 方式（两个 service 都是可注入构造，无需自造假类）：
/// - SettingsService：`SharedPreferences.setMockInitialValues` + 真实例
/// - StorageService：临时目录（测试里不点导入 / 设置，实际不会读写）
Future<void> pumpHome(WidgetTester tester, TimetableData data) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsService settings = SettingsService(prefs);
  // J6：HomeScreen 新增 required themeService（透传给设置页）
  final ThemeService themeService = ThemeService(prefs);
  // ⚠️ testWidgets 跑在 fake async zone 里：真实文件 I/O 的 Future 永远不会完成，
  // 必须用 tester.runAsync 包起来，否则整条测试会静默挂死（踩过）。
  final Directory tmp = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('home_swipe_test'),
  ))!;
  final StorageService storage = StorageService(directory: tmp);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
          initialData: data,
          storage: storage,
          settings: settings,
          themeService: themeService,
        ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('左滑翻到下一周', (WidgetTester tester) async {
    // 今天是第 7 周
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('第 7 周'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await _settle(tester);

    expect(find.text('第 8 周'), findsOneWidget);
  });

  testWidgets('右滑翻到上一周', (WidgetTester tester) async {
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('第 7 周'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await _settle(tester);

    expect(find.text('第 6 周'), findsOneWidget);
  });

  testWidgets('第 1 周右滑只回弹，不越界', (WidgetTester tester) async {
    // 本周一就是第一周周一 → 今天是第 1 周
    await pumpHome(tester, buildData(weeksAgo: 0));
    expect(find.text('第 1 周'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(300, 0), 1000);
    await _settle(tester);

    // BouncingScrollPhysics 给出回弹反馈，但周次不变
    expect(find.text('第 1 周'), findsOneWidget);
  });

  testWidgets('最后一周左滑只回弹，不越界', (WidgetTester tester) async {
    // 19 周前开学 → 今天是第 20 周（共 20 周）
    await pumpHome(tester, buildData(weeksAgo: 19));
    expect(find.text('第 20 周'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await _settle(tester);

    expect(find.text('第 20 周'), findsOneWidget);
  });

  testWidgets('点「>」按钮翻到下一周（原行为不回归）', (WidgetTester tester) async {
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('第 7 周'), findsOneWidget);

    await tester.tap(find.byTooltip('下一周'));
    await _settle(tester);

    expect(find.text('第 8 周'), findsOneWidget);
  });

  testWidgets('点「<」按钮翻到上一周（原行为不回归）', (WidgetTester tester) async {
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('第 7 周'), findsOneWidget);

    await tester.tap(find.byTooltip('上一周'));
    await _settle(tester);

    expect(find.text('第 6 周'), findsOneWidget);
  });

  testWidgets('已是本周时「回到本周」不可见', (WidgetTester tester) async {
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('第 7 周'), findsOneWidget);

    expect(find.text('回到本周'), findsNothing);
  });

  testWidgets('滑到别的周后「回到本周」出现，点击后回到本周', (WidgetTester tester) async {
    await pumpHome(tester, buildData(weeksAgo: 6));
    expect(find.text('回到本周'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await _settle(tester);
    expect(find.text('第 8 周'), findsOneWidget);

    // 不在本周了 → 按钮出现
    expect(find.text('回到本周'), findsOneWidget);

    await tester.tap(find.text('回到本周'));
    await _settle(tester);

    expect(find.text('第 7 周'), findsOneWidget);
    // 回到本周后按钮再次隐藏
    expect(find.text('回到本周'), findsNothing);
  });
}
