import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/widgets/palette_pack_sheet.dart';

/// 课程配色面板验收：平板/手机两种视口 + 色块预览数量（每行 ≤6）+
/// 内置/导入行差异 + 点选生效。
void main() {
  Future<PaletteService> newService() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return PaletteService(prefs);
  }

  void setViewport(WidgetTester tester, Size logical, double dpr) {
    tester.view.physicalSize = logical * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
  }

  Future<void> openSheet(WidgetTester tester, PaletteService service) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => PalettePackSheet.show(
                  ctx,
                  service: service,
                  onImport: () {},
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
    testWidgets('内容限宽 480，不铺满', (WidgetTester tester) async {
      setViewport(tester, const Size(900, 1200), 2.0);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      final Size size = tester.getSize(find.byType(PalettePackSheet));
      expect(size.width, lessThanOrEqualTo(480.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('手机视口（411×914dp）', () {
    testWidgets('铺满宽度、内容完整不溢出', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      final Size size = tester.getSize(find.byType(PalettePackSheet));
      expect(size.width, greaterThan(400.0));
      expect(size.width, lessThanOrEqualTo(411.0));
      expect(find.text('课程配色'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('导入配色…'), findsOneWidget);
      expect(find.text('内置'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('色块预览', () {
    testWidgets('每行最多 6 个色块（3 个内置包 = 3×6 = 18）', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      // 3 个内置包分别为 16 / 12 / 12 色，都超过 6：
      // 不截断会渲染 40 个色块，截断后必须是 3 × 6 = 18
      expect(find.byType(PaletteSwatches), findsNWidgets(3));
      expect(find.byType(PaletteSwatch), findsNWidgets(18));
      expect(tester.takeException(), isNull);
    });
  });

  group('内置 / 导入行的差异', () {
    testWidgets('内置行也有 ⋯ 菜单按钮，菜单未开时无删除图标', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      // 3 个内置行都有「⋯」；删除动作收在菜单里，未展开时不可见
      expect(find.byIcon(Icons.more_vert), findsNWidgets(3));
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入行 ⋯ 菜单有三项（重命名 / 复制 JSON / 删除）', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await service.importFromJson(
        '{"name":"夜色","colors":['
        '"#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      // 第 4 行（index 3）是导入包「夜色」
      await tester.tap(find.byIcon(Icons.more_vert).at(3));
      await tester.pumpAndSettle();

      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('复制 JSON'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('夜色'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('主题包临时包（theme: 前缀）行没有 ⋯ 按钮', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await service.applyFromTheme(
        ThemePack(
          id: 'night',
          name: '夜色主题',
          seedColor: 0xFF112233,
          coursePalette: <int>[
            0xFFC05B5B,
            0xFFB8528C,
            0xFF8E55A8,
            0xFF5A68B0,
            0xFF4278B5,
            0xFF328CAE,
            0xFF2C9186,
            0xFF3E8A55,
          ],
        ),
      );
      await openSheet(tester, service);

      // 临时包插在最前（只读视图，无 ⋯）；只有 3 个内置行有 ⋯
      expect(find.text('夜色主题'), findsOneWidget);
      expect(find.text('主题包'), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('⋯ 菜单管理动作', () {
    testWidgets('内置行菜单只有「复制 JSON」', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 默认（内置）
      await tester.pumpAndSettle();

      expect(find.text('复制 JSON'), findsOneWidget);
      expect(find.text('重命名'), findsNothing);
      expect(find.text('删除'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('重命名流程：⋯ -> 重命名 -> 新名生效', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"id":"pc","name":"我的配色","colors":['
        '"#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '我的配色'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '新配色');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.text('新配色'), findsOneWidget);
      expect(find.text('已重命名为「新配色」'), findsOneWidget);
      expect(service.imported.value.single.name, '新配色');
      expect(service.imported.value.single.id, outcome.pack!.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('纯空白名 -> 不提交、无提示', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await service.importFromJson(
        '{"name":"我的配色","colors":['
        '"#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      await tester.tap(find.byIcon(Icons.more_vert).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(service.imported.value.single.name, '我的配色');
      expect(find.textContaining('已重命名'), findsNothing);
    });

    testWidgets('复制 JSON -> 剪贴板是可再导入的合法 JSON', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

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

      await tester.tap(find.byIcon(Icons.more_vert).at(0)); // 默认（内置）
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制 JSON'));
      await tester.pumpAndSettle();

      expect(find.text('已复制到剪贴板，可发给同学导入'), findsOneWidget);
      expect(copied, isNotNull);
      // 往返闸门：复制的 JSON 能再次导入还原成同一个包
      final PalettePack? parsed = PalettePack.fromJson(jsonDecode(copied!));
      expect(parsed, isNotNull);
      expect(parsed!.name, '默认');
      expect(parsed.colors, PalettePack.builtins.first.colors);
      expect(tester.takeException(), isNull);
    });
  });

  group('点选生效', () {
    testWidgets('点某行 -> service.active 变成它', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      expect(service.active.value.id, 'default');
      await tester.tap(find.text('莫兰迪'));
      await tester.pumpAndSettle();

      expect(service.active.value.id, 'morandi');
      expect(tester.takeException(), isNull);
    });
  });
}
