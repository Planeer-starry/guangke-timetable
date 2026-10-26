import 'dart:convert';

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
  // WidgetService.resolveBrightness('system') 会读 WidgetsBinding，
  // 普通 test() 不会自动初始化 binding，必须显式建一次。
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('widgetSkinPayload（下发 payload，含实际生效亮暗）', () {
    test('mode 原样写入：light / dark 固定，system 也传 system', () {
      final ThemePack pack = ThemePack.builtins.first;
      // light / dark 必须原样下发：App 强制深色时小组件要跟着深色
      for (final String mode in <String>['light', 'dark']) {
        final Map<String, dynamic> json =
            jsonDecode(widgetSkinPayload(pack, themeMode: mode))
                as Map<String, dynamic>;
        expect(json['mode'], mode);
        expect(json['light'], isA<Map<String, dynamic>>());
        expect(json['dark'], isA<Map<String, dynamic>>());
      }
      // system 必须保留原样（不能解析成固定亮度）：App 没运行时系统切主题，
      // 只有 Kotlin 每次现读 uiMode 才能跟上
      final Map<String, dynamic> sys =
          jsonDecode(widgetSkinPayload(pack, themeMode: 'system'))
              as Map<String, dynamic>;
      expect(sys['mode'], 'system');
    });

    test('未知 themeMode 归一成 system（不会写出脏值）', () {
      final Map<String, dynamic> json =
          jsonDecode(widgetSkinPayload(ThemePack.builtins.first,
                  themeMode: 'weird-value'))
              as Map<String, dynamic>;
      expect(json['mode'], 'system');
    });

    test('dark 套与 widgetSkinFromTheme 对应结果一致', () {
      final ThemePack pack = ThemePack.builtins[1];
      final ({WidgetSkin light, WidgetSkin dark}) skins = widgetSkinFromTheme(pack);
      final Map<String, dynamic> darkJson =
          jsonDecode(widgetSkinPayload(pack, themeMode: 'dark'))
              as Map<String, dynamic>;
      final Map<String, dynamic> darkSet =
          darkJson['dark'] as Map<String, dynamic>;
      expect(darkSet['card'], skins.dark.card.toString());
      expect(darkSet['title'], skins.dark.title.toString());
    });

    // 契约测试：Kotlin 的 WidgetColors.skinOf 只认这三个顶层键
    // （light / dark / mode）。任何一侧改名都会让皮肤静默失效 ——
    // 表现就是「小组件不跟随主题」，所以这里钉死键名。
    test('顶层键契约与 Kotlin skinOf 一致（light / dark / mode）', () {
      final Map<String, dynamic> json =
          jsonDecode(widgetSkinPayload(ThemePack.builtins.first,
                  themeMode: 'dark'))
              as Map<String, dynamic>;
      expect(
        json.keys.toSet(),
        <String>{'light', 'dark', 'mode'},
        reason: '改了键名要同步改 android/.../WidgetColors.kt 的 skinOf',
      );
    });

    test('payload 里颜色仍是可被 toLongOrNull 解析的十进制字符串', () {
      final Map<String, dynamic> json =
          jsonDecode(widgetSkinPayload(ThemePack.builtins.first,
                  themeMode: 'light'))
              as Map<String, dynamic>;
      for (final String key in <String>['light', 'dark']) {
        final Map<String, dynamic> set = json[key] as Map<String, dynamic>;
        for (final String field in <String>[
          'card', 'title', 'sub', 'divider', 'gridEmpty', 'accent',
        ]) {
          expect(int.tryParse(set[field] as String), isNotNull,
              reason: '$key.$field 不是十进制整数');
        }
      }
    });
  });
}

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
