import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:timetable/models/theme_pack.dart';

/// 小组件皮肤：一组颜色角色（ARGB int），由主题包派生（J9）。
///
/// 字段语义（Kotlin 侧按同名键读取）：
/// - [card]：卡片背景（Android 12+ 经 backgroundTintList 套在圆角 shape 上）
/// - [title]：主文字（课名 / 空态主文案）
/// - [sub]：次文字（表头 / 时间 / 地点 / 行标签）
/// - [divider]：分隔线（一周总课表）
/// - [gridEmpty]：周网格空格子底色
/// - [accent]：强调色（今日列高亮 / 空态色条）
class WidgetSkin {
  const WidgetSkin({
    required this.card,
    required this.title,
    required this.sub,
    required this.divider,
    required this.gridEmpty,
    required this.accent,
  });

  final int card;
  final int title;
  final int sub;
  final int divider;
  final int gridEmpty;
  final int accent;

  /// 序列化给 Kotlin：ARGB int 的十进制字符串。
  ///
  /// 与课程色同套路：Dart int 是 64 位，ARGB 值可能超过 Kotlin Int.MAX，
  /// Kotlin 侧 `toLongOrNull().toInt()` 还原 32 位位模式。
  Map<String, String> toJson() => <String, String>{
    'card': card.toString(),
    'title': title.toString(),
    'sub': sub.toString(),
    'divider': divider.toString(),
    'gridEmpty': gridEmpty.toString(),
    'accent': accent.toString(),
  };
}

/// 由主题包算亮 / 暗两套小组件皮肤。
///
/// 对比度不手算：直接用 `ColorScheme.fromSeed`（Material 3）的角色色，
/// onSurface / onSurfaceVariant 在 surfaceContainer 系底色上的对比度
/// 由规范保证（测试闸门兜底：title vs card >= 4.5、sub vs card >= 3.5）。
({WidgetSkin light, WidgetSkin dark}) widgetSkinFromTheme(ThemePack pack) {
  final Color seed = Color(pack.seedColor);
  return (
    light: _skinOf(
      pack,
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
    ),
    dark: _skinOf(
      pack,
      ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
    ),
  );
}

WidgetSkin _skinOf(ThemePack pack, ColorScheme colors) {
  return WidgetSkin(
    card: colors.surfaceContainerLow.toARGB32(),
    title: colors.onSurface.toARGB32(),
    sub: colors.onSurfaceVariant.toARGB32(),
    divider: colors.outlineVariant.toARGB32(),
    gridEmpty: colors.surfaceContainerHighest.toARGB32(),
    accent: _accentOf(pack, colors).toARGB32(),
  );
}

/// 生成下发小组件的皮肤 payload（纯函数，便于单测）。
///
/// 结构：`{"light":{…},"dark":{…},"mode":"system"|"light"|"dark"}`
///
/// [themeMode] 是用户选的**主题模式**，不是解析后的亮度 —— 这一点很关键：
/// - `light` / `dark`：App 强制指定，小组件必须跟着用同一套，
///   否则会出现「App 深色、小组件亮色」；
/// - `system`：小组件要**实时**跟随系统深浅色。下发的若是某个固定亮度值，
///   App 没运行、系统切了主题时会挑到陈旧的那一套，所以必须把 `system`
///   原样传下去，让 Kotlin 每次渲染时现读 `uiMode`。
String widgetSkinPayload(ThemePack pack, {required String themeMode}) {
  final ({WidgetSkin light, WidgetSkin dark}) skins = widgetSkinFromTheme(pack);
  final String mode = switch (themeMode) {
    'light' || 'dark' => themeMode,
    _ => 'system',
  };
  return jsonEncode(<String, dynamic>{
    'light': skins.light.toJson(),
    'dark': skins.dark.toJson(),
    'mode': mode,
  });
}

/// 强调色：主题包显式指定则用之；否则取该亮暗度下的 Material 3
/// 品牌色（primary，fromSeed 会调整色调保证与角色色和谐，比直接用
/// seedColor 在卡片上的对比度更稳）。
Color _accentOf(ThemePack pack, ColorScheme colors) {
  final int? widgetAccent = pack.widgetAccent;
  return widgetAccent != null ? Color(widgetAccent) : colors.primary;
}

/// WCAG 相对亮度对比度（4.5 = 正文 AA；3.5 ≈ 大字 AA 放宽档）。
/// 测试闸门用，App 运行时不调用。
double widgetContrastRatio(int argbA, int argbB) {
  final double la = _relativeLuminance(argbA);
  final double lb = _relativeLuminance(argbB);
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(int argb) {
  double linearize(int v255) {
    final double s = v255 / 255;
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize((argb >> 16) & 0xFF) +
      0.7152 * linearize((argb >> 8) & 0xFF) +
      0.0722 * linearize(argb & 0xFF);
}
