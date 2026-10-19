import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/utils/widget_skin.dart';

/// 六套内置包 × 亮暗两套，展开成 (包名, 亮度标签, 皮肤) 列表。
List<(String, String, WidgetSkin)> _builtinSkinCases() {
  final List<(String, String, WidgetSkin)> cases =
      <(String, String, WidgetSkin)>[];
  for (final ThemePack pack in ThemePack.builtins) {
    final ({WidgetSkin light, WidgetSkin dark}) skins = widgetSkinFromTheme(
      pack,
    );
    cases.add((pack.name, 'light', skins.light));
    cases.add((pack.name, 'dark', skins.dark));
  }
  return cases;
}

void main() {
  group('widgetSkinFromTheme', () {
    test('六套内置包 light/dark 六字段非 0', () {
      for (final (String packName, String label, WidgetSkin skin)
          in _builtinSkinCases()) {
        for (final MapEntry<String, int> field in _fieldsOf(skin).entries) {
          expect(
            field.value,
            isNot(0),
            reason: '$packName $label 的 ${field.key} 为 0（透明色）',
          );
        }
      }
    });

    test('对比度闸门：title vs card >= 4.5、sub vs card >= 3.5', () {
      for (final (String packName, String label, WidgetSkin skin)
          in _builtinSkinCases()) {
        final double titleRatio = widgetContrastRatio(skin.title, skin.card);
        expect(
          titleRatio,
          greaterThanOrEqualTo(4.5),
          reason: '$packName $label：title 对比度 $titleRatio < 4.5',
        );
        final double subRatio = widgetContrastRatio(skin.sub, skin.card);
        expect(
          subRatio,
          greaterThanOrEqualTo(3.5),
          reason: '$packName $label：sub 对比度 $subRatio < 3.5',
        );
      }
    });

    test('accent 跟随显式指定的 widgetAccent', () {
      const ThemePack pack = ThemePack(
        id: 'custom_accent',
        name: '自定义强调色',
        seedColor: 0xFF3F51B5,
        widgetAccent: 0xFF112233,
      );
      final ({WidgetSkin light, WidgetSkin dark}) skins = widgetSkinFromTheme(
        pack,
      );
      expect(skins.light.accent, 0xFF112233);
      expect(skins.dark.accent, 0xFF112233);
    });

    test('widgetAccent 为 null 时 accent = fromSeed(brightness).primary', () {
      const ThemePack pack = ThemePack(
        id: 'custom_no_accent',
        name: '未指定强调色',
        seedColor: 0xFF35754F,
      );
      final ({WidgetSkin light, WidgetSkin dark}) skins = widgetSkinFromTheme(
        pack,
      );
      expect(
        skins.light.accent,
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF35754F),
          brightness: Brightness.light,
        ).primary.toARGB32(),
      );
      expect(
        skins.dark.accent,
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF35754F),
          brightness: Brightness.dark,
        ).primary.toARGB32(),
      );
    });

    test('seedColor 相同幂等（两次计算结果一致）', () {
      for (final ThemePack pack in ThemePack.builtins) {
        final ({WidgetSkin light, WidgetSkin dark}) first = widgetSkinFromTheme(
          pack,
        );
        final ({WidgetSkin light, WidgetSkin dark}) second =
            widgetSkinFromTheme(pack);
        expect(first.light.toJson(), second.light.toJson(), reason: pack.name);
        expect(first.dark.toJson(), second.dark.toJson(), reason: pack.name);
      }
    });

    test('toJson 值可被 Kotlin toLongOrNull 解析（纯十进制整数）', () {
      for (final (String packName, String label, WidgetSkin skin)
          in _builtinSkinCases()) {
        for (final MapEntry<String, String> entry in skin.toJson().entries) {
          expect(
            int.tryParse(entry.value),
            isNotNull,
            reason: '$packName $label 的 ${entry.key} 不是十进制整数',
          );
        }
      }
    });
  });
}

/// 六字段按名展开（「非 0」用例用）。
Map<String, int> _fieldsOf(WidgetSkin skin) {
  return <String, int>{
    'card': skin.card,
    'title': skin.title,
    'sub': skin.sub,
    'divider': skin.divider,
    'gridEmpty': skin.gridEmpty,
    'accent': skin.accent,
  };
}
