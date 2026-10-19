import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/screens/pack_manager_screen.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/services/theme_service.dart';

/// 管理页验收（J8）：tab 切换 / 内置与导入行的菜单差异 / 重命名流程。
void main() {
  /// pump 出管理页，返回构造好的两个 service（供断言）。
  Future<(ThemeService, PaletteService)> pumpManager(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemeService themeService = ThemeService(prefs);
    final PaletteService paletteService = PaletteService(prefs);
    await tester.pumpWidget(
      MaterialApp(
        home: PackManagerScreen(
          themeService: themeService,
          paletteService: paletteService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (themeService, paletteService);
  }

  /// 打开第 [index] 行的「更多操作」菜单（0 = 第一行）。
  Future<void> openRowMenu(WidgetTester tester, int index) async {
    await tester.tap(find.byIcon(Icons.more_vert).at(index));
    await tester.pumpAndSettle();
  }

  testWidgets('两个 tab 能切换', (WidgetTester tester) async {
    await pumpManager(tester);
    // 默认主题包 tab：内置 6 套可见，配色 tab 未渲染
    expect(find.text('靛蓝'), findsOneWidget);
    expect(find.text('莫兰迪'), findsNothing);

    await tester.tap(find.text('课程配色'));
    await tester.pumpAndSettle();

    expect(find.text('莫兰迪'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(find.text('靛蓝'), findsNothing);
  });

  testWidgets('内置行菜单只有「复制 JSON」', (WidgetTester tester) async {
    await pumpManager(tester);
    // 第一行 = 内置「靛蓝」
    await openRowMenu(tester, 0);

    expect(find.text('重命名'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.text('复制 JSON'), findsOneWidget);

    // 点菜单屏障关闭，不影响后续断言
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('导入行菜单三项都有', (WidgetTester tester) async {
    final (themeService, _) = await pumpManager(tester);
    await themeService.importFromJson('{"name":"夜色","seedColor":"#112233"}');
    await tester.pumpAndSettle();

    // 导入行在列表末尾（6 内置 + 1 导入）
    await openRowMenu(tester, 6);

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('复制 JSON'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('重命名流程：输入新名确定 -> 列表与 service 都更新', (WidgetTester tester) async {
    final (themeService, _) = await pumpManager(tester);
    final ImportOutcome outcome = await themeService.importFromJson(
      '{"name":"夜色","seedColor":"#112233"}',
    );
    await tester.pumpAndSettle();

    await openRowMenu(tester, 6);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    // 对话框：预填当前名、autofocus
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '夜色改');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(find.text('夜色改'), findsOneWidget);
    expect(themeService.imported.value.single.name, '夜色改');
    expect(themeService.imported.value.single.id, outcome.pack!.id);
    expect(find.text('已重命名为「夜色改」'), findsOneWidget);
  });

  testWidgets('重命名为纯空白 -> 不提交、无提示', (WidgetTester tester) async {
    final (themeService, _) = await pumpManager(tester);
    await themeService.importFromJson('{"name":"夜色","seedColor":"#112233"}');
    await tester.pumpAndSettle();

    await openRowMenu(tester, 6);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(themeService.imported.value.single.name, '夜色');
    expect(find.text('夜色'), findsOneWidget);
    expect(find.textContaining('已重命名'), findsNothing);
  });
}
