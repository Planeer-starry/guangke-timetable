import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/palette_pack.dart';

/// 内置配色的质量闸门（J7）：每个颜色对白字的对比度必须 >= 3.5:1。
///
/// 课块文字一律白色（course_color.dart 的设计决策），配色必须保证可读。
/// WCAG 相对对比度：C = (L1 + 0.05) / (L2 + 0.05)，白字取 L1 = 1.0。
/// 大字号 AA 门槛 3:1，这里用 3.5:1 留余量。
double _channel(int v) {
  final double c = v / 255.0;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int argb) {
  final double r = _channel((argb >> 16) & 0xFF);
  final double g = _channel((argb >> 8) & 0xFF);
  final double b = _channel(argb & 0xFF);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// 该颜色上放白字的对比度。
double contrastWithWhite(int argb) => 1.05 / (_luminance(argb) + 0.05);

void main() {
  group('内置配色白字对比度闸门', () {
    test('内置 3 套全部颜色 >= 3.5:1', () {
      for (final PalettePack pack in PalettePack.builtins) {
        for (final int color in pack.colors) {
          expect(
            contrastWithWhite(color),
            greaterThanOrEqualTo(3.5),
            reason:
                '「${pack.name}」颜色 ${color.toRadixString(16)} '
                '白字对比度 ${contrastWithWhite(color).toStringAsFixed(2)}:1 不足 3.5:1',
          );
        }
      }
    });

    test('内置色对比度整体区间合理（3.5 ~ 8.0，无过深失控色）', () {
      for (final PalettePack pack in PalettePack.builtins) {
        for (final int color in pack.colors) {
          final double c = contrastWithWhite(color);
          expect(c, lessThan(8.0), reason: '「${pack.name}」颜色过深（$c:1），黑底观感会失衡');
        }
      }
    });
  });
}
