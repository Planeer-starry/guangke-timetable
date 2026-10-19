import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    testWidgets('只有内置包时无删除按钮', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await openSheet(tester, service);

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('导入包行有删除按钮 + 「含课程配色」标注', (WidgetTester tester) async {
      setViewport(tester, const Size(411, 914), 2.625);
      final ThemeService service = await newService();
      await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233","coursePalette":'
        '["#C05B5B","#B8528C","#8E55A8","#5A68B0",'
        '"#4278B5","#328CAE","#2C9186","#3E8A55"]}',
      );
      await openSheet(tester, service);

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.text('夜色'), findsOneWidget);
      expect(find.text('导入 · 含课程配色'), findsOneWidget);
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
