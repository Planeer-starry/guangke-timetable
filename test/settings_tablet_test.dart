import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/settings_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/undo_stack.dart';

/// 「学期已配置」的最小课表（meta 三件套齐）。
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

/// pump 出设置页。
///
/// mock 方式（全部可注入，无需自造假类）：
/// - PackageInfo.setMockInitialValues（API 见 pub-cache 10.2.2 源码，
///   五个 required 参数），否则 _loadPackageInfo 的平台通道会抛异常；
/// - SettingsService：SharedPreferences.setMockInitialValues + 真实例；
/// - StorageService：临时目录（测试里不点危险操作，实际不会读写）。
Future<void> pumpSettings(WidgetTester tester) async {
  PackageInfo.setMockInitialValues(
    appName: '广科课表',
    packageName: 'com.planeer.timetable',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SettingsService settings = SettingsService(
    await SharedPreferences.getInstance(),
  );
  // ⚠️ testWidgets 跑在 fake async zone 里：真实文件 I/O 的 Future 永远不会完成，
  // 必须用 tester.runAsync 包起来，否则整条测试会静默挂死（同 home_swipe_week_test，
  // 这个坑已经踩过一次，见那里的注释）。
  final Directory tmp = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('settings_tablet_test'),
  ))!;
  final StorageService storage = StorageService(directory: tmp);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        data: ValueNotifier<TimetableData>(_configuredData()),
        storage: storage,
        settings: settings,
        undoStack: UndoStack(),
        initialUpdate: null,
      ),
    ),
  );
  // _loadPackageInfo 是异步的，settle 让 setState 生效
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('平板尺寸（1500×1060）下设置页呈双栏卡片', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1500, 1060);
    addTearDown(tester.view.reset);

    await pumpSettings(tester);

    // isUpdateEnabled=false（updateInfoUrl 为空）：左列学期+外观、
    // 右列课表+关于，共 4 张分组卡片——单列布局没有 Card，
    // 4 张即证明走了双栏分支
    expect(find.byType(Card), findsNWidgets(4));
    // 分组标题仍然齐全（内容同源，不因双栏丢项）
    expect(find.text('学期'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('课表'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('手机尺寸（400×800）下设置页保持单列（无卡片）', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);

    await pumpSettings(tester);

    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('学期'), findsOneWidget);
  });
}
