import 'dart:async';

import 'package:flutter/material.dart';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/home_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/widget_service.dart';

/// 应用入口。
///
/// 初始化两个 service、加载课表，用顶层 `ValueNotifier` 承载数据
/// （状态管理只用 ValueNotifier / ValueListenableBuilder，不引库）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final StorageService storage = await StorageService.forApp();
  final SettingsService settings = await SettingsService.forApp();
  final TimetableData data = await storage.load();
  // 启动即同步一次小组件数据（精确闹钟可用性只提示，不阻塞启动）
  unawaited(WidgetService.refreshAll(data));
  runApp(TimetableApp(initialData: data, storage: storage, settings: settings));
}

/// 根组件：监听 [SettingsService.themeModeListenable]，
/// 让 MaterialApp.themeMode 随用户在设置页的选择即时切换。
class TimetableApp extends StatefulWidget {
  const TimetableApp({
    super.key,
    required this.initialData,
    required this.storage,
    required this.settings,
  });

  final TimetableData initialData;
  final StorageService storage;
  final SettingsService settings;

  @override
  State<TimetableApp> createState() => _TimetableAppState();
}

class _TimetableAppState extends State<TimetableApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeOf(widget.settings.themeMode);
    widget.settings.themeModeListenable.addListener(_onThemeModeChanged);
  }

  @override
  void dispose() {
    widget.settings.themeModeListenable.removeListener(_onThemeModeChanged);
    super.dispose();
  }

  void _onThemeModeChanged() {
    setState(() {
      _themeMode = _themeModeOf(widget.settings.themeModeListenable.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '广科课表',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: HomeScreen(
        initialData: widget.initialData,
        storage: widget.storage,
        settings: widget.settings,
      ),
    );
  }

  /// 'system' / 'light' / 'dark' → ThemeMode。
  static ThemeMode _themeModeOf(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
