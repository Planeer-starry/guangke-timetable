import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/theme_pack.dart';

void main() {
  group('parseColor', () {
    test('int 直接返回', () {
      expect(ThemePack.parseColor(0xFF3F51B5), 0xFF3F51B5);
      expect(ThemePack.parseColor(0xFFFFFFFF), 0xFFFFFFFF);
      expect(ThemePack.parseColor(1), 1);
    });

    test('#RRGGBB 补不透明 FF', () {
      expect(ThemePack.parseColor('#3F51B5'), 0xFF3F51B5);
      expect(ThemePack.parseColor('#000001'), 0xFF000001);
    });

    test('#AARRGGBB 直接返回', () {
      expect(ThemePack.parseColor('#803F51B5'), 0x803F51B5);
      expect(ThemePack.parseColor('#FF3F51B5'), 0xFF3F51B5);
    });

    test('小写 hex 同样可解析', () {
      expect(ThemePack.parseColor('#ff0000'), 0xFFFF0000);
      expect(ThemePack.parseColor('#80ff0000'), 0x80FF0000);
    });

    test('0 / 负数 / 超范围 -> null', () {
      expect(ThemePack.parseColor(0), isNull);
      expect(ThemePack.parseColor(-1), isNull);
      expect(ThemePack.parseColor(0x100000000), isNull);
    });

    test('null -> null', () {
      expect(ThemePack.parseColor(null), isNull);
    });

    test('位数不对 / 缺 # -> null', () {
      expect(ThemePack.parseColor('#12345'), isNull);
      expect(ThemePack.parseColor('#1234567'), isNull);
      expect(ThemePack.parseColor('#123456789'), isNull);
      expect(ThemePack.parseColor('3F51B5'), isNull);
      expect(ThemePack.parseColor('#GGGGGG'), isNull);
      expect(ThemePack.parseColor(''), isNull);
    });
  });

  group('parsePalette', () {
    test('合法 8 色', () {
      final List<int> eight = List<int>.generate(8, (int i) => 0xFF000000 + i);
      expect(ThemePack.parsePalette(eight), eight);
    });

    test('合法 24 色', () {
      final List<int> twentyFour = List<int>.generate(
        24,
        (int i) => 0xFF000000 + i,
      );
      expect(ThemePack.parsePalette(twentyFour), twentyFour);
    });

    test('少于 8 个 -> null', () {
      expect(
        ThemePack.parsePalette(<int>[0xFF000001, 0xFF000002, 0xFF000003]),
        isNull,
      );
    });

    test('多于 24 个 -> null', () {
      final List<int> tooMany = List<int>.generate(
        25,
        (int i) => 0xFF000000 + i,
      );
      expect(ThemePack.parsePalette(tooMany), isNull);
    });

    test('含非法元素 -> null', () {
      final List<Object> mixed = <Object>[
        for (int i = 0; i < 7; i++) 0xFF000000 + i,
        '#zzzzzz',
      ];
      expect(ThemePack.parsePalette(mixed), isNull);
    });

    test('非数组 -> null', () {
      expect(ThemePack.parsePalette('#FF0000'), isNull);
      expect(ThemePack.parsePalette(5), isNull);
      expect(ThemePack.parsePalette(null), isNull);
      expect(ThemePack.parsePalette(<String, dynamic>{'a': 1}), isNull);
    });
  });

  group('fromJson', () {
    test('正常解析全字段', () {
      final ThemePack? pack = ThemePack.fromJson(<String, dynamic>{
        'id': 'my-theme',
        'name': '我的主题',
        'seedColor': '#3F51B5',
        'coursePalette': <String>[
          '#C05B5B',
          '#B8528C',
          '#8E55A8',
          '#5A68B0',
          '#4278B5',
          '#328CAE',
          '#2C9186',
          '#3E8A55',
        ],
        'widgetAccent': '#FF8800',
      });
      expect(pack, isNotNull);
      expect(pack!.id, 'my-theme');
      expect(pack.name, '我的主题');
      expect(pack.seedColor, 0xFF3F51B5);
      expect(pack.coursePalette, isNotNull);
      expect(pack.coursePalette!.length, 8);
      expect(pack.coursePalette!.first, 0xFFC05B5B);
      expect(pack.widgetAccent, 0xFFFF8800);
      expect(pack.builtin, isFalse);
    });

    test('缺 name -> null', () {
      expect(
        ThemePack.fromJson(<String, dynamic>{'seedColor': '#112233'}),
        isNull,
      );
    });

    test('name 空串 / 空白串 -> null', () {
      expect(
        ThemePack.fromJson(<String, dynamic>{
          'name': '',
          'seedColor': '#112233',
        }),
        isNull,
      );
      expect(
        ThemePack.fromJson(<String, dynamic>{
          'name': '   ',
          'seedColor': '#112233',
        }),
        isNull,
      );
    });

    test('缺 seedColor / seedColor 非法 -> null', () {
      expect(ThemePack.fromJson(<String, dynamic>{'name': '夜色'}), isNull);
      expect(
        ThemePack.fromJson(<String, dynamic>{
          'name': '夜色',
          'seedColor': '#12345',
        }),
        isNull,
      );
      expect(
        ThemePack.fromJson(<String, dynamic>{'name': '夜色', 'seedColor': 0}),
        isNull,
      );
    });

    test('顶层非对象 -> null', () {
      expect(ThemePack.fromJson(<dynamic>[1, 2]), isNull);
      expect(ThemePack.fromJson('x'), isNull);
      expect(ThemePack.fromJson(3), isNull);
      expect(ThemePack.fromJson(null), isNull);
    });

    test('id 缺省时按 name 派生', () {
      final ThemePack? pack = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': 0xFF123456,
      });
      expect(pack, isNotNull);
      expect(pack!.id, 'imported_${'夜色'.hashCode.toRadixString(16)}');
    });

    test('coursePalette 无效 -> 包仍导入、palette 置 null', () {
      final ThemePack? pack = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#123456',
        'coursePalette': <String>['#FF0000'],
      });
      expect(pack, isNotNull);
      expect(pack!.coursePalette, isNull);
      expect(pack.seedColor, 0xFF123456);
    });

    test('toJson -> fromJson 往返一致', () {
      final ThemePack pack = ThemePack.fromJson(<String, dynamic>{
        'id': 'round-trip',
        'name': '往返',
        'seedColor': 0xFF35754F,
        'coursePalette': <int>[for (int i = 0; i < 8; i++) 0xFF000000 + i],
        'widgetAccent': 0xFF7A5CC0,
      })!;
      final ThemePack? round = ThemePack.fromJson(pack.toJson());
      expect(round, isNotNull);
      expect(round!.id, 'round-trip');
      expect(round.name, pack.name);
      expect(round.seedColor, pack.seedColor);
      expect(round.coursePalette, pack.coursePalette);
      expect(round.widgetAccent, pack.widgetAccent);
      expect(round.builtin, isFalse);
    });
  });

  group('内置包', () {
    test('共 6 个、id 唯一、fallback == first', () {
      expect(ThemePack.builtins, hasLength(6));
      expect(
        ThemePack.builtins.map((ThemePack p) => p.id).toSet(),
        hasLength(6),
      );
      expect(ThemePack.fallback, same(ThemePack.builtins.first));
      expect(ThemePack.fallback.id, 'indigo');
    });

    test('内置包不带 coursePalette / widgetAccent，builtin = true', () {
      for (final ThemePack pack in ThemePack.builtins) {
        expect(pack.coursePalette, isNull);
        expect(pack.widgetAccent, isNull);
        expect(pack.builtin, isTrue);
      }
    });

    test('byId：内置 / 导入 / 不存在', () {
      final ThemePack? builtin = ThemePack.byId('forest', const <ThemePack>[]);
      expect(builtin, isNotNull);
      expect(builtin!.name, '墨绿');

      final ThemePack imported = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#112233',
      })!;
      expect(
        ThemePack.byId(imported.id, <ThemePack>[imported]),
        same(imported),
      );
      expect(ThemePack.byId('no-such-id', const <ThemePack>[]), isNull);
    });
  });

  group('相等性（防止 ValueNotifier 跳过更新）', () {
    // 回归用例：曾经「按 id 判等」，导致同 id 覆盖时
    // ValueNotifier.value 的 setter 认为值没变而跳过赋值，
    // 颜色改了但界面和小组件都不刷新。
    test('同 id 但 seedColor 不同 -> 不相等', () {
      const ThemePack a = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
      );
      const ThemePack b = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF222222,
      );
      expect(a == b, isFalse);
      expect(a.hashCode == b.hashCode, isFalse);
    });

    test('同 id 但名称不同 -> 不相等', () {
      const ThemePack a = ThemePack(id: 'x', name: '夜色', seedColor: 0xFF111111);
      const ThemePack b = ThemePack(id: 'x', name: '夜色改', seedColor: 0xFF111111);
      expect(a == b, isFalse);
    });

    test('同 id 但课程配色不同 -> 不相等；配色相同 -> 相等', () {
      final List<int> palette = <int>[
        for (int i = 0; i < 8; i++) 0xFF000000 + i,
      ];
      final ThemePack withPalette = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
        coursePalette: palette,
      );
      final ThemePack withoutPalette = const ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
      );
      expect(withPalette == withoutPalette, isFalse);

      final ThemePack samePalette = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
        coursePalette: List<int>.of(palette),
      );
      expect(withPalette, samePalette); // 逐元素相同即相等
    });

    test('所有字段都相同 -> 相等且 hashCode 一致', () {
      final ThemePack a = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
        coursePalette: <int>[for (int i = 0; i < 8; i++) 0xFF000000 + i],
        widgetAccent: 0xFF123456,
      );
      final ThemePack b = ThemePack(
        id: 'x',
        name: '夜色',
        seedColor: 0xFF111111,
        coursePalette: <int>[for (int i = 0; i < 8; i++) 0xFF000000 + i],
        widgetAccent: 0xFF123456,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
