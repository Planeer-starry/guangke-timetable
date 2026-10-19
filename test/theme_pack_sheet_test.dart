import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/widgets/theme_pack_sheet.dart';

/// 主题包面板验收：平板/手机两种视口 + 内置/导入行差异 + 点选生效。
void main() {
  Future<ThemeService> newService() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return ThemeService(prefs);
  }

  void setViewport(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> openSheet(WidgetTester tester, ThemeService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    ThemePackSheet.show(ctx, service: service, onImport: () {}),
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
    testWidgets('内容限宽 480，不铺满', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      final Size size = tester.getSize(find.byType(ThemePackSheet));
      expect(size.width, lessThanOrEqualTo(480.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('手机视口（411×914dp）', () {
    testWidgets('铺满宽度、内容完整不溢出', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      final Size size = tester.getSize(find.byType(ThemePackSheet));
      expect(size.width, greaterThan(400.0));
      expect(size.width, lessThanOrEqualTo(411.0));
      expect(find.text('主题包'), findsOneWidget);
      expect(find.text('靛蓝'), findsOneWidget);
      expect(find.text('导入主题包…'), findsOneWidget);
      expect(find.text('内置'), findsNWidgets(6));
      expect(tester.takeException(), isNull);
    });
  });

  group('内置 / 导入行的差异', () {
    testWidgets('内置行也有 ⋯ 菜单按钮，菜单未开时无删除图标', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      // 6 个内置行都有「⋯」；删除动作收在菜单里，未展开时不可见
      expect(find.byIcon(Icons.more_vert), findsNWidgets(6));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入行 ⋯ 菜单有三项（重命名 / 复制 JSON / 删除）', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233","coursePalette":'
        '["#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      // 第 7 行（index 6）是导入包「夜色」
      await tester.tap(find.byIcon(Icons.more_vert).at(6));
      await tester.pumpAndSettle();

      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('复制 JSON'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('夜色'), findsOneWidget);
      expect(find.text('导入 · 含课程配色'), findsOneWidget);
      // 点菜单外关闭，不影响后续用例
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });
  });

  group('⋯ 菜单管理动作', () {
    testWidgets('内置行菜单只有「复制 JSON」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 靛蓝（内置）
      await tester.pumpAndSettle();

      expect(find.text('复制 JSON'), findsOneWidget);
      expect(find.text('重命名'), findsNothing);
      expect(find.text('删除'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('重命名流程：⋯ -> 重命名 -> 新名生效', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      final ImportOutcome outcome = await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233"}',
      );
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      // 对话框预填当前名
      expect(find.widgetWithText(TextField, '夜色'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '夜色改');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('夜色改'), findsOneWidget);
      expect(find.text('已重命名为「夜色改」'), findsOneWidget);
      expect(service.imported.value.single.name, '夜色改');
      expect(service.imported.value.single.id, outcome.pack!.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('纯空白名 -> 不提交、无提示', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await service.importFromJson('{"name":"夜色","seedColor":"#112233"}');
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(service.imported.value.single.name, '夜色');
      expect(find.text('夜色'), findsOneWidget);
      expect(find.textContaining('已重命名'), findsNothing);
    });

    testWidgets('复制 JSON -> 剪贴板是可再导入的合法 JSON', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      // 拦截 Clipboard.setData 平台通道，捕获复制的文本
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall call,
          ) async {
            if (call.method == 'Clipboard.setData') {
              copied =
                  (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 靛蓝（内置）
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制 JSON'));
      await tester.pumpAndSettle();

      expect(find.text('已复制到剪贴板，可发给同学导入'), findsOneWidget);
      expect(copied, isNotNull);
      // 往返闸门：复制的 JSON 能再次导入还原成同一个包
      final ThemePack? parsed = ThemePack.fromJson(jsonDecode(copied!));
      expect(parsed, isNotNull);
      expect(parsed!.name, '靛蓝');
      expect(parsed.seedColor, ThemePack.builtins.first.seedColor);
      expect(tester.takeException(), isNull);
    });
  });

  group('点选生效', () {
    testWidgets('点某行 -> service.active 变成它', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      expect(service.active.value.id, 'indigo');
      await tester.tap(find.text('墨绿'));
      await tester.pumpAndSettle();

      expect(service.active.value.id, 'forest');
      expect(tester.takeException(), isNull);
    });
  });
}
