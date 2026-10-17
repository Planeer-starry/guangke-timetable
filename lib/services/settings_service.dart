import 'package:shared_preferences/shared_preferences.dart';

/// UI 偏好设置（shared_preferences）。
///
/// 注意（AGENTS.md 5.1「单一真源」）：学期参数
/// （school / semesterName / week1Monday / totalWeeks）的唯一真源是
/// `timetable.json` 的 `meta`，**禁止**在这里另存一份。
/// 这里只放 UI 偏好（当前查看周次、主题模式）。
class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  /// App 运行时便利工厂；测试请直接构造并传 mock 实例
  /// （`SharedPreferences.setMockInitialValues({})`）。
  static Future<SettingsService> forApp() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  static const String _keyWeekOverride = 'week_override';
  static const String _keyThemeMode = 'theme_mode';

  /// 用户主动固定显示的周次；null 表示跟随日历（默认）。
  int? get weekOverride => _prefs.getInt(_keyWeekOverride);

  /// 写入周次覆盖；传 null 表示清除覆盖。
  Future<void> setWeekOverride(int? week) async {
    if (week == null) {
      await _prefs.remove(_keyWeekOverride);
    } else {
      await _prefs.setInt(_keyWeekOverride, week);
    }
  }

  /// 主题模式：`system`（跟随系统）/ `light` / `dark`。
  String get themeMode => _prefs.getString(_keyThemeMode) ?? 'system';

  /// 写入主题模式。
  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(_keyThemeMode, mode);
  }
}
