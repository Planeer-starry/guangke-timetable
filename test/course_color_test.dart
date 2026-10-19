import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/utils/course_color.dart';

/// 自定义 8 色（0x11~0x88 灰阶，与默认 16 色零交集，
/// 便于断言「只返回这 8 色」与「旧默认色不再被识别」）。
const List<int> _custom8 = <int>[
  0xFF111111,
  0xFF222222,
  0xFF333333,
  0xFF444444,
  0xFF555555,
  0xFF666666,
  0xFF777777,
  0xFF888888,
];

void main() {
  // 调色板是模块级可变状态：每个测试前恢复默认，避免互相污染
  setUp(() {
    setActiveCoursePalette(null);
  });

  group('colorValueFromName（默认调色板）', () {
    test('同名课程颜色稳定', () {
      expect(colorValueFromName('计算机网络'), colorValueFromName('计算机网络'));
    });

    test('结果落在调色板内', () {
      expect(defaultCoursePalette.contains(colorValueFromName('高等数学')), isTrue);
      expect(defaultCoursePalette.contains(colorValueFromName('大学英语')), isTrue);
    });

    test('空字符串安全处理', () {
      expect(colorValueFromName(''), defaultCoursePalette.first);
    });

    test('不同课程名可得到不同颜色', () {
      final Set<int> colors = <int>{
        colorValueFromName('计算机网络'),
        colorValueFromName('高等数学'),
        colorValueFromName('大学英语'),
        colorValueFromName('体育'),
      };
      expect(colors.length, greaterThan(1));
    });
  });

  group('setActiveCoursePalette', () {
    test('默认状态 usingDefaultPalette 为 true', () {
      expect(usingDefaultPalette, isTrue);
      expect(activeCoursePalette, same(defaultCoursePalette));
    });

    test('null -> 恢复默认', () {
      setActiveCoursePalette(_custom8);
      expect(usingDefaultPalette, isFalse);
      setActiveCoursePalette(null);
      expect(usingDefaultPalette, isTrue);
      expect(defaultCoursePalette.contains(colorValueFromName('高等数学')), isTrue);
    });

    test('自定义 8 色 -> colorValueFromName 只返回这 8 色里的', () {
      setActiveCoursePalette(_custom8);
      expect(usingDefaultPalette, isFalse);
      const List<String> names = <String>[
        '计算机网络',
        '高等数学',
        '大学英语',
        '体育',
        '军事理论',
        '数据结构',
        '操作系统',
        '线性代数',
        '毛概',
        '大学英语听力',
      ];
      final Set<int> customSet = _custom8.toSet();
      for (final String name in names) {
        expect(customSet.contains(colorValueFromName(name)), isTrue);
      }
      // 空字符串返回自定义调色板首色
      expect(colorValueFromName(''), _custom8.first);
    });

    test('isPaletteColor 跟着新调色板走', () {
      setActiveCoursePalette(_custom8);
      expect(isPaletteColor(0xFF111111), isTrue);
      expect(isPaletteColor(0xFF888888), isTrue);
      // 默认调色板里的颜色不再被识别
      expect(isPaletteColor(0xFFC05B5B), isFalse);
      expect(isPaletteColor(0xFF857B2E), isFalse);
      // 恢复默认后又识别
      setActiveCoursePalette(null);
      expect(isPaletteColor(0xFFC05B5B), isTrue);
      expect(isPaletteColor(0xFF111111), isFalse);
    });

    test('空列表 -> 忽略，保持原调色板', () {
      setActiveCoursePalette(_custom8);
      setActiveCoursePalette(<int>[]);
      expect(usingDefaultPalette, isFalse);
      expect(colorValueFromName(''), _custom8.first);
      // 恢复默认后空列表同样被忽略
      setActiveCoursePalette(null);
      setActiveCoursePalette(<int>[]);
      expect(usingDefaultPalette, isTrue);
    });

    test('传入列表被拷贝，外部修改不泄漏', () {
      final List<int> mutable = <int>[..._custom8];
      setActiveCoursePalette(mutable);
      mutable[0] = 0xFFABCDEF;
      expect(activeCoursePalette[0], 0xFF111111);
    });
  });
}
