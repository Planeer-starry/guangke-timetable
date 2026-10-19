import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/home_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/course_color.dart';

/// 应用入口。
///
/// 初始化 service、加载课表，用顶层 `ValueNotifier` 承载数据
/// （状态管理只用 ValueNotifier / ValueListenableBuilder，不引库）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final StorageService storage = await StorageService.forApp();
  final SettingsService settings = await SettingsService.forApp();
  // SharedPreferences 是单例，这里拿到的是与 SettingsService 同一个实例
  final ThemeService themeService = ThemeService(
    await SharedPreferences.getInstance(),
  );
  // ⚠️ 必须在 storage.load() **之前**：load 内部的配色迁移
  // （_migratePalette）按「当前调色板」判断旧 colorValue 是否过时并按
  // 课名重取——先设好主题包调色板，重启后旧课表才会迁移到主题包配色。
  setActiveCoursePalette(themeService.active.value.coursePalette);
  WidgetService.setAccent(themeService.active.value);
  final TimetableData data = await storage.load();
  // 启动即同步一次小组件数据（精确闹钟可用性只提示，不阻塞启动）
  unawaited(WidgetService.refreshAll(data));
  runApp(
    TimetableApp(
      initialData: data,
      storage: storage,
      settings: settings,
      themeService: themeService,
    ),
  );
}

/// 根组件：监听 [SettingsService.themeModeListenable] 与
/// [ThemeService.active]，让 MaterialApp 的 themeMode / 种子色
/// 随用户选择即时切换。
class TimetableApp extends StatefulWidget {
  const TimetableApp({
    super.key,
    required this.initialData,
    required this.storage,
    required this.settings,
    required this.themeService,
  });

  final TimetableData initialData;
  final StorageService storage;
  final SettingsService settings;
  final ThemeService themeService;

  @override
  State<TimetableApp> createState() => _TimetableAppState();
}

class _TimetableAppState extends State<TimetableApp> {
  late ThemeMode _themeMode;
  ThemePack _themePack = ThemePack.fallback;

  @override
  void initState() {
    super.initState();
    _themeMode = _themeModeOf(widget.settings.themeMode);
    _themePack = widget.themeService.active.value;
    widget.settings.themeModeListenable.addListener(_onThemeModeChanged);
    widget.themeService.active.addListener(_onThemePackChanged);
  }

  @override
  void dispose() {
    widget.settings.themeModeListenable.removeListener(_onThemeModeChanged);
    widget.themeService.active.removeListener(_onThemePackChanged);
    super.dispose();
  }

  void _onThemeModeChanged() {
    setState(() {
      _themeMode = _themeModeOf(widget.settings.themeModeListenable.value);
    });
  }

  /// 主题包切换：重建整套 ColorScheme（MaterialApp 级）。
  ///
  /// 小组件强调色与课程重取色由设置页的监听统一处理
  /// （它持有 data notifier 与 refreshAll 入口）。
  void _onThemePackChanged() {
    setState(() {
      _themePack = widget.themeService.active.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int seed = _themePack.seedColor;
    return MaterialApp(
      title: '简课表',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(seed)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color(seed),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      home: HomeScreen(
        initialData: widget.initialData,
        storage: widget.storage,
        settings: widget.settings,
        themeService: widget.themeService,
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
