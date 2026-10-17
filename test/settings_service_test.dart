import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timetable/services/settings_service.dart';

void main() {
  Future<SettingsService> newSettings() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  test('默认值：未覆盖周次、主题跟随系统', () async {
    final SettingsService settings = await newSettings();
    expect(settings.weekOverride, isNull);
    expect(settings.themeMode, 'system');
  });

  test('写入周次覆盖后能读回', () async {
    final SettingsService settings = await newSettings();
    await settings.setWeekOverride(5);
    expect(settings.weekOverride, 5);
  });

  test('传 null 清除周次覆盖', () async {
    final SettingsService settings = await newSettings();
    await settings.setWeekOverride(5);
    await settings.setWeekOverride(null);
    expect(settings.weekOverride, isNull);
  });

  test('主题写入后能读回', () async {
    final SettingsService settings = await newSettings();
    await settings.setThemeMode('dark');
    expect(settings.themeMode, 'dark');
  });
}
