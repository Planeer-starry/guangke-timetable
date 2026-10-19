import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/utils/course_color.dart';

void main() {
  group('parseColors', () {
    test('8 个颜色（下边界）通过', () {
      final List<String> eight = List<String>.generate(
        8,
        (int i) => '#11${i.toRadixString(16).padLeft(2, '0')}22',
      );
      expect(PalettePack.parseColors(eight), isNotNull);
      expect(PalettePack.parseColors(eight)!.length, 8);
    });

    test('24 个颜色（上边界）通过', () {
      final List<int> twentyFour = List<int>.generate(
        24,
        (int i) => 0xFF000000 + i,
      );
      expect(PalettePack.parseColors(twentyFour), isNotNull);
      expect(PalettePack.parseColors(twentyFour)!.length, 24);
    });

    test('7 个颜色拒绝', () {
      final List<int> seven = List<int>.generate(7, (int i) => 0xFF000000 + i);
      expect(PalettePack.parseColors(seven), isNull);
    });

    test('25 个颜色拒绝', () {
      final List<int> twentyFive = List<int>.generate(
        25,
        (int i) => 0xFF000000 + i,
      );
      expect(PalettePack.parseColors(twentyFive), isNull);
    });

    test('含非法元素拒绝', () {
      final List<Object> mixed = <Object>[
        for (int i = 0; i < 7; i++) 0xFF000000 + i,
        '#zzzzzz',
      ];
      expect(PalettePack.parseColors(mixed), isNull);
    });

    test('非数组拒绝', () {
      expect(PalettePack.parseColors('#FF0000'), isNull);
      expect(PalettePack.parseColors(5), isNull);
      expect(PalettePack.parseColors(null), isNull);
      expect(PalettePack.parseColors(<String, dynamic>{'a': 1}), isNull);
    });

    test('元素解析规则与 ThemePack.parseColor 一致（int / #RGB / #ARGB）', () {
      expect(
        PalettePack.parseColors(<Object>[
          0xFFC05B5B,
          '#B8528C',
          '#808E55A8',
          for (int i = 0; i < 5; i++) 0xFF000000 + i,
        ]),
        isNotNull,
      );
    });
  });

  group('fromJson', () {
    test('对象形式正常解析', () {
      final PalettePack? pack = PalettePack.fromJson(<String, dynamic>{
        'id': 'my-palette',
        'name': '我的配色',
        'colors': <String>[
          '#C05B5B',
          '#B8528C',
          '#8E55A8',
          '#5A68B0',
          '#4278B5',
          '#328CAE',
          '#2C9186',
          '#3E8A55',
        ],
      });
      expect(pack, isNotNull);
      expect(pack!.id, 'my-palette');
      expect(pack.name, '我的配色');
      expect(pack.colors, hasLength(8));
      expect(pack.colors.first, 0xFFC05B5B);
      expect(pack.builtin, isFalse);
    });

    test('裸数组：name 自动派生「导入配色 N 色」', () {
      final PalettePack? pack = PalettePack.fromJson(<dynamic>[
        for (int i = 0; i < 10; i++)
          '#10${i.toRadixString(16).padLeft(2, '0')}20',
      ]);
      expect(pack, isNotNull);
      expect(pack!.name, '导入配色 10 色');
      expect(pack.colors, hasLength(10));
      expect(pack.builtin, isFalse);
      expect(pack.id, isNotEmpty);
    });

    test('缺 name -> null', () {
      expect(
        PalettePack.fromJson(<String, dynamic>{
          'colors': <String>[
            '#C05B5B',
            '#B8528C',
            '#8E55A8',
            '#5A68B0',
            '#4278B5',
            '#328CAE',
            '#2C9186',
            '#3E8A55',
          ],
        }),
        isNull,
      );
    });

    test('name 空串 / 空白串 -> null', () {
      const List<String> colors = <String>[
        '#C05B5B',
        '#B8528C',
        '#8E55A8',
        '#5A68B0',
        '#4278B5',
        '#328CAE',
        '#2C9186',
        '#3E8A55',
      ];
      expect(
        PalettePack.fromJson(<String, dynamic>{'name': '', 'colors': colors}),
        isNull,
      );
      expect(
        PalettePack.fromJson(<String, dynamic>{
          'name': '   ',
          'colors': colors,
        }),
        isNull,
      );
    });

    test('colors 无效（数量 / 元素）-> null', () {
      expect(
        PalettePack.fromJson(<String, dynamic>{
          'name': '我的配色',
          'colors': <String>['#FF0000'],
        }),
        isNull,
      );
      expect(
        PalettePack.fromJson(<String, dynamic>{
          'name': '我的配色',
          'colors': <String>[
            '#C05B5B',
            '#B8528C',
            '#8E55A8',
            '#5A68B0',
            '#4278B5',
            '#328CAE',
            '#2C9186',
            '不是颜色',
          ],
        }),
        isNull,
      );
    });

    test('裸数组但颜色无效 -> null', () {
      expect(PalettePack.fromJson(<dynamic>['#FF0000', '#00FF00']), isNull);
    });

    test('顶层是字符串 / 数字 / null -> null', () {
      expect(PalettePack.fromJson('x'), isNull);
      expect(PalettePack.fromJson(3), isNull);
      expect(PalettePack.fromJson(null), isNull);
    });

    test('toJson -> fromJson 往返一致', () {
      final PalettePack pack = PalettePack.fromJson(<String, dynamic>{
        'id': 'round-trip',
        'name': '往返',
        'colors': <int>[for (int i = 0; i < 8; i++) 0xFF000000 + i],
      })!;
      final PalettePack? round = PalettePack.fromJson(pack.toJson());
      expect(round, isNotNull);
      expect(round!.id, 'round-trip');
      expect(round.name, pack.name);
      expect(round.colors, pack.colors);
      expect(round.builtin, isFalse);
    });
  });

  group('值语义判等（防 J6 的 ValueNotifier 跳过通知坑）', () {
    test('同 id 但 colors 不同 -> 不相等', () {
      const List<int> colorsA = <int>[
        0xFF111111,
        0xFF222222,
        0xFF333333,
        0xFF444444,
        0xFF555555,
        0xFF666666,
        0xFF777777,
        0xFF888888,
      ];
      final List<int> colorsB = <int>[...colorsA]..[0] = 0xFFABCDEF;
      const PalettePack a = PalettePack(id: 'p', name: 'P', colors: colorsA);
      final PalettePack b = PalettePack(id: 'p', name: 'P', colors: colorsB);
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('全字段相同才相等；name / builtin 不同也不等', () {
      const List<int> colors = <int>[
        0xFF111111,
        0xFF222222,
        0xFF333333,
        0xFF444444,
        0xFF555555,
        0xFF666666,
        0xFF777777,
        0xFF888888,
      ];
      const PalettePack a = PalettePack(id: 'p', name: 'P', colors: colors);
      const PalettePack same = PalettePack(id: 'p', name: 'P', colors: colors);
      expect(a == same, isTrue);

      const PalettePack diffName = PalettePack(
        id: 'p',
        name: 'Q',
        colors: colors,
      );
      expect(a == diffName, isFalse);

      const PalettePack diffBuiltin = PalettePack(
        id: 'p',
        name: 'P',
        colors: colors,
        builtin: true,
      );
      expect(a == diffBuiltin, isFalse);
    });
  });

  group('内置配色', () {
    test('共 3 套、id 唯一、fallback 是 default', () {
      expect(PalettePack.builtins, hasLength(3));
      expect(
        PalettePack.builtins.map((PalettePack p) => p.id).toSet(),
        hasLength(3),
      );
      expect(PalettePack.fallback, same(PalettePack.builtins.first));
      expect(PalettePack.fallback.id, 'default');
      expect(PalettePack.fallback.name, '默认');
    });

    test('颜色数量与值正确（default 复用 defaultCoursePalette）', () {
      expect(PalettePack.builtins[0].colors, same(defaultCoursePalette));
      expect(PalettePack.builtins[1].colors, hasLength(12));
      expect(PalettePack.builtins[2].colors, hasLength(12));
      expect(PalettePack.builtins[1].colors.first, 0xFF8C6A5D);
      expect(PalettePack.builtins[2].colors.first, 0xFFA05A34);
      for (final PalettePack pack in PalettePack.builtins) {
        expect(pack.builtin, isTrue);
      }
    });

    test('byId：内置 / 导入 / 不存在', () {
      expect(PalettePack.byId('morandi', const <PalettePack>[]), isNotNull);
      final PalettePack imported = PalettePack.fromJson(<dynamic>[
        for (int i = 0; i < 8; i++) 0xFF000000 + i,
      ])!;
      expect(
        PalettePack.byId(imported.id, <PalettePack>[imported]),
        same(imported),
      );
      expect(PalettePack.byId('no-such', const <PalettePack>[]), isNull);
    });
  });
}
