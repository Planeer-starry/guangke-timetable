import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/settings_screen.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/services/undo_stack.dart';

/// 「课程配色」设置行的 subtitle 验收（J7 批 2）：
/// 普通配色显示名称，主题包注入的临时包（`theme:` 前缀）显示「来自主题包」。

/// 「学期已配置」的最小课表（同 settings_tablet_test）。
TimetableData _configuredData() {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': <Map<String, dynamic>>[],
    'overrides': <Map<String, dynamic>>[],
  });
}

/// 全新的 mock SharedPreferences。
Future<SharedPreferences> _newPrefs() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}

/// pump 出设置页（依赖同 settings_tablet_test：PackageInfo / prefs /
/// 临时目录），paletteService 由调用方构造（两种前缀场景各不同）。
Future<void> pumpSettings(
  WidgetTester tester,
  SharedPreferences prefs,
  PaletteService paletteService, {
  ThemeService? themeService,
}) async {
  PackageInfo.setMockInitialValues(
    appName: '简课表',
    packageName: 'com.planeer.timetable',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  final SettingsService settings = SettingsService(prefs);
  final ThemeService resolvedTheme = themeService ?? ThemeService(prefs);
  // ⚠️ testWidgets 跑在 fake async zone 里：真实文件 I/O 的 Future 永远不会完成，
  // 必须用 tester.runAsync 包起来（同 settings_tablet_test，踩过的坑）。
  final Directory tmp = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('settings_palette_ui_test'),
  ))!;
  final StorageService storage = StorageService(directory: tmp);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        data: ValueNotifier<TimetableData>(_configuredData()),
        storage: storage,
        settings: settings,
        themeService: resolvedTheme,
        paletteService: paletteService,
        undoStack: UndoStack(),
        initialUpdate: null,
      ),
    ),
  );
  // _loadPackageInfo 是异步的，settle 让 setState 生效
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('「课程配色」行显示当前配色名（默认）', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final SharedPreferences prefs = await _newPrefs();
    // 全新安装：palette_id 不存在 → active 回退内置「默认」
    final PaletteService paletteService = PaletteService(prefs);
    await pumpSettings(tester, prefs, paletteService);

    expect(find.text('课程配色'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主题包注入的配色（theme: 前缀）显示「来自主题包」', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final SharedPreferences prefs = await _newPrefs();
    // 1.3.0 迁移路径：palette_id 不存在 + 主题包带配色
    // → active = theme:<themeId> 临时包（不落盘）
    final ThemePack theme = ThemePack(
      id: 'ye',
      name: '夜色',
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
    );
    final PaletteService paletteService = PaletteService(
      prefs,
      themeForMigration: theme,
    );
    expect(paletteService.active.value.id, 'theme:ye');
    await pumpSettings(tester, prefs, paletteService);

    expect(find.text('课程配色'), findsOneWidget);
    expect(find.text('来自主题包'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重命名正在使用的主题包 -> 用户自选的课程配色不被注入覆盖',
      (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    final SharedPreferences prefs = await _newPrefs();

    // 用户自选「莫兰迪」（palette_id = morandi）
    final PaletteService paletteService = PaletteService(prefs);
    await paletteService.select(PalettePack.builtins[1]);
    expect(paletteService.active.value.id, 'morandi');

    // 另有一个带课程配色的主题包，且它是当前激活的主题
    final ThemeService themeService = ThemeService(prefs);
    final ThemePack theme = ThemePack(
      id: 'ye',
      name: '夜色',
      seedColor: 0xFF112233,
      coursePalette: <int>[
        0xFFC05B5B, 0xFFB8528C, 0xFF8E55A8, 0xFF5A68B0,
        0xFF4278B5, 0xFF328CAE, 0xFF2C9186, 0xFF3E8A55,
      ],
    );
    await themeService.importFromJson(jsonEncode(theme.toJson()));
    expect(themeService.active.value.id, 'ye');

    await pumpSettings(tester, prefs, paletteService, themeService: themeService);
    // initState 把 _lastThemeId 初始化为当前主题，之后同一 id 的变化
    // 视为「数据更新」而不是「切换主题」

    // 重命名（只改 name，seedColor / coursePalette 不变）
    await themeService.rename(themeService.active.value, '夜色改名');
    await tester.pumpAndSettle();
    expect(themeService.active.value.name, '夜色改名');

    // 关键断言：调色板仍是用户自选的莫兰迪，没被主题包配色冲掉
    expect(
      paletteService.active.value.id,
      'morandi',
      reason: '重命名不该触发 applyFromTheme（J8 边界 bug）',
    );
    expect(tester.takeException(), isNull);
  });
}
