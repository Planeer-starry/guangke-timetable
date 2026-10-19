import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/settings_screen.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/services/undo_stack.dart';

/// 「导出课表」（J11）入口验收：行存在、底部弹窗两动作、复制有反馈。

TimetableData _dataWithCourse() {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'c_001',
        'name': '计算机网络',
        'teacher': '张三',
        'location': '教学楼A101',
        'colorValue': 4294198070,
        'dayWeek': 1,
        'sectionStart': 3,
        'sectionEnd': 4,
        'weekMask': 65535,
        'note': '',
      },
    ],
    'overrides': <Map<String, dynamic>>[],
  });
}

/// pump 出设置页（依赖同 settings_tablet_test：PackageInfo / prefs / 临时目录）。
Future<void> pumpSettings(WidgetTester tester) async {
  PackageInfo.setMockInitialValues(
    appName: '简课表',
    packageName: 'com.planeer.timetable',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final SettingsService settings = SettingsService(prefs);
  final ThemeService themeService = ThemeService(prefs);
  final PaletteService paletteService = PaletteService(prefs);
  // ⚠️ testWidgets 跑在 fake async zone 里：真实文件 I/O 的 Future 永远不会完成，
  // 必须用 tester.runAsync 包起来（同 settings_tablet_test，踩过的坑）。
  final Directory tmp = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('settings_export_test'),
  ))!;
  final StorageService storage = StorageService(directory: tmp);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        data: ValueNotifier<TimetableData>(_dataWithCourse()),
        storage: storage,
        settings: settings,
        themeService: themeService,
        paletteService: paletteService,
        undoStack: UndoStack(),
        initialUpdate: null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('「导出课表」行存在，点开面板显示两个动作', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await pumpSettings(tester);

    expect(find.text('导出课表'), findsOneWidget);
    expect(find.textContaining('换手机时导入即可完整恢复'), findsOneWidget);

    await tester.tap(find.text('导出课表'));
    await tester.pumpAndSettle();

    expect(find.text('复制到剪贴板'), findsOneWidget);
    expect(find.text('保存为文件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('复制到剪贴板 → 提示已复制', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    // Clipboard.setData 走 platform channel，测试里必须 mock
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );

    await pumpSettings(tester);

    await tester.tap(find.text('导出课表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制到剪贴板'));
    await tester.pumpAndSettle();

    expect(find.text('已复制，可直接发给自己'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
