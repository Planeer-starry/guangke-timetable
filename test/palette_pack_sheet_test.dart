import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    testWidgets('只有内置包时无删除按钮', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await openSheet(tester, service);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入包行有删除按钮 + 「导入」来源标注', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final PaletteService service = await newService();
      await service.importFromJson(
        '{"name":"夜色","colors":['
        '"#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('夜色'), findsOneWidget);
      expect(find.text('导入'), findsOneWidget);
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
