import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/utils/course_color.dart';

/// 一套稳定的自定义 8 色（#111111..#888888，与内置 3 套零交集，
/// 便于断言切换生效）。直接写成 **JSON 数组文本**。
///
/// ⚠️ 不要写成 `List<String>` 再用 `.toString()` 拼进 JSON：Dart 的
/// `List.toString()` 产出 `[#111111, #222222]` —— 色值没有引号，不是合法
/// JSON，`jsonDecode` 会在第一个色值处报 `Unexpected character`。
/// 这个坑已经让 5 条用例误报「实现有问题」过一次。
const String _custom8Json =
    '["#111111","#222222","#333333","#444444",'
    '"#555555","#666666","#777777","#888888"]';

/// 主题包配色 JSON（8 色另一组，与 _custom8 交集为空）。
const String _themePaletteJson =
    '["#9A1111","#9A2222","#9A3333","#9A4444",'
    '"#9A5555","#9A6666","#9A7777","#9A8888"]';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // course_color 的模块级调色板状态隔离：每测前恢复默认
    setActiveCoursePalette(null);
  });

  group('PaletteService 默认与恢复', () {
    test('默认 active == fallback 且调色板被应用', () async {
      // 先污染模块级调色板，构造 service 后应被恢复成默认
      setActiveCoursePalette(<int>[for (int i = 0; i < 8; i++) 0xFF000000 + i]);
      expect(usingDefaultPalette, isFalse);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      expect(service.active.value.id, 'default');
      expect(service.active.value, same(PalettePack.fallback));
      expect(usingDefaultPalette, isTrue);
      expect(service.imported.value, isEmpty);
      expect(service.all, hasLength(3));
    });

    test('select 持久化（重建 service 仍是它）且调色板已切换', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.select(PalettePack.builtins[1]); // 莫兰迪

      expect(service.active.value.id, 'morandi');
      expect(activeCoursePalette, PalettePack.builtins[1].colors);
      expect(usingDefaultPalette, isFalse);

      final PaletteService restored = PaletteService(prefs);
      expect(restored.active.value.id, 'morandi');
      expect(activeCoursePalette, PalettePack.builtins[1].colors);
    });
  });

  group('importFromJson', () {
    test('对象形式导入 -> ok、立刻生效、持久化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"name":"我的配色","colors":$_themePaletteJson}',
      );
      expect(outcome.ok, isTrue);
      expect(outcome.error, isNull);
      expect(outcome.pack, isNotNull);
      expect(service.imported.value, hasLength(1));
      expect(service.active.value.id, outcome.pack!.id);
      expect(activeCoursePalette, outcome.pack!.colors);

      final PaletteService restored = PaletteService(prefs);
      expect(restored.imported.value, hasLength(1));
      expect(restored.active.value.id, outcome.pack!.id);
    });

    test('裸数组导入 -> 自动命名「导入配色 8 色」', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        _custom8Json,
      );
      expect(outcome.ok, isTrue);
      expect(outcome.pack!.name, '导入配色 8 色');
      expect(service.active.value.name, '导入配色 8 色');
      expect(activeCoursePalette, outcome.pack!.colors);
    });

    test('同 id 导入 -> 覆盖旧包且 active 刷新', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.importFromJson(
        '{"id":"p1","name":"配色一","colors":$_custom8Json}',
      );
      // 同 id、不同颜色：值语义 == 会判定 active 变化，通知必须发出
      final PaletteImportOutcome second = await service.importFromJson(
        '{"id":"p1","name":"配色一","colors":$_themePaletteJson}',
      );
      expect(second.ok, isTrue);
      expect(service.imported.value, hasLength(1));
      expect(service.active.value.colors, second.pack!.colors);
      expect(activeCoursePalette, second.pack!.colors);
    });

    test('非法 JSON -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '这不是json',
      );
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('不是有效的 JSON'));
      expect(service.imported.value, isEmpty);
    });

    test('顶层既不是对象也不是数组 -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '"#FF0000"',
      );
      expect(outcome.error, '配色包必须是 JSON 对象或颜色数组');
    });

    test('对象缺 name -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"colors":$_custom8Json}',
      );
      expect(outcome.error, '缺少必要字段（需要 name 和 colors）');
    });

    test('colors 无效 -> 直接 error，不用默认凑数', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      // 数量不足
      expect(
        (await service.importFromJson('{"name":"坏","colors":["#FF0000"]}'))
            .error,
        '颜色无效（需 8~24 个颜色值）',
      );
      // 元素非法
      expect(
        (await service.importFromJson(
          '{"name":"坏","colors":["#zz1111","#222222","#333333","#444444",'
          '"#555555","#666666","#777777","#888888"]}',
        )).error,
        '颜色无效（需 8~24 个颜色值）',
      );
      expect(service.imported.value, isEmpty);
    });

    test('id 与内置冲突 -> error（带内置包名）', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"id":"morandi","name":"假莫兰迪","colors":$_custom8Json}',
      );
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('内置配色「莫兰迪」'));
      expect(service.imported.value, isEmpty);
    });
  });

  group('remove', () {
    test('remove 导入包（非 active）-> imported 移除、active 不变', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome a = await service.importFromJson(
        '{"id":"pa","name":"A","colors":$_custom8Json}',
      );
      final PaletteImportOutcome b = await service.importFromJson(
        '{"id":"pb","name":"B","colors":$_themePaletteJson}',
      );
      expect(a.ok, isTrue);
      expect(b.ok, isTrue);
      expect(service.imported.value, hasLength(2));
      // active 是 b（最后导入即选中）；删 a 不影响 active
      await service.remove(a.pack!);
      expect(service.imported.value, hasLength(1));
      expect(service.imported.value.single.id, 'pb');
      expect(service.active.value.id, 'pb');

      final PaletteService restored = PaletteService(prefs);
      expect(restored.imported.value, hasLength(1));
    });

    test('remove 正在用的包 -> active 回退 fallback 且调色板已切换', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"name":"我的配色","colors":$_custom8Json}',
      );
      expect(service.active.value.id, outcome.pack!.id);
      await service.remove(outcome.pack!);

      expect(service.active.value.id, 'default');
      expect(activeCoursePalette, defaultCoursePalette);
      expect(usingDefaultPalette, isTrue);

      final PaletteService restored = PaletteService(prefs);
      expect(restored.active.value.id, 'default');
    });

    test('remove 内置包 -> 无变化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.select(PalettePack.builtins[2]); // 秋日
      await service.remove(PalettePack.builtins[2]);
      expect(service.active.value.id, 'autumn');
      expect(service.imported.value, isEmpty);
      expect(service.all, hasLength(3));
    });
  });

  group('rename', () {
    test('重命名导入包 -> name 变、id 不变、持久化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"id":"pc","name":"我的配色","colors":$_custom8Json}',
      );
      await service.rename(outcome.pack!, '新配色');
      expect(service.imported.value.single.name, '新配色');
      expect(service.imported.value.single.id, 'pc');
      expect(service.imported.value.single.colors, outcome.pack!.colors);

      final PaletteService restored = PaletteService(prefs);
      expect(restored.imported.value.single.name, '新配色');
    });

    test('重命名正在用的包 -> active.name 同步变化、调色板不变', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"id":"pc","name":"我的配色","colors":$_custom8Json}',
      );
      // importFromJson 成功即选中，此刻 active 就是它
      await service.rename(outcome.pack!, '新配色');
      expect(service.active.value.id, 'pc');
      expect(service.active.value.name, '新配色');
      expect(service.active.value.colors, outcome.pack!.colors);
      expect(activeCoursePalette, outcome.pack!.colors);
    });

    test('空白新名 -> 直接 return 无变化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PaletteImportOutcome outcome = await service.importFromJson(
        '{"id":"pc","name":"我的配色","colors":$_custom8Json}',
      );
      await service.rename(outcome.pack!, '   ');
      expect(service.imported.value.single.name, '我的配色');
      expect(service.active.value.name, '我的配色');

      final PaletteService restored = PaletteService(prefs);
      expect(restored.imported.value.single.name, '我的配色');
    });

    test('rename 内置包 -> 直接 return 无变化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.rename(PalettePack.builtins.first, '假默认');
      expect(service.imported.value, isEmpty);
      expect(service.active.value.name, '默认');
      expect(PalettePack.builtins.first.name, '默认');
    });
  });

  group('损坏数据防御', () {
    test('预置损坏的 palette_packs -> 不抛、imported 为空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'palette_packs': '{{{不是json',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      expect(service.imported.value, isEmpty);
      expect(service.active.value.id, 'default');
    });

    test('预置 palette_packs 混入垃圾元素 -> 只留合法项', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'palette_packs':
            '[{"name":"好的","colors":$_themePaletteJson}, 42, null, "x", '
            '{"name":"","colors":[]}]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      expect(service.imported.value, hasLength(1));
      expect(service.imported.value.single.name, '好的');
    });

    test('palette_id 指向不存在的包 -> 回退 fallback', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'palette_id': 'ghost',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      expect(service.active.value.id, 'default');
    });
  });

  group('1.3.0 迁移（themeForMigration）', () {
    test('无 palette_id 且主题包带配色 -> active 是主题包配色', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#112233',
        'coursePalette': <String>[
          '#9A1111',
          '#9A2222',
          '#9A3333',
          '#9A4444',
          '#9A5555',
          '#9A6666',
          '#9A7777',
          '#9A8888',
        ],
      })!;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(
        prefs,
        themeForMigration: theme,
      );
      expect(service.active.value.id, startsWith('theme:'));
      expect(service.active.value.name, '夜色');
      expect(service.active.value.colors, theme.coursePalette);
      expect(activeCoursePalette, theme.coursePalette);
      // 临时包不在导入列表
      expect(service.imported.value, isEmpty);
    });

    test('无 palette_id 但主题包无配色 -> fallback 默认', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '素色',
        'seedColor': '#112233',
      })!;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(
        prefs,
        themeForMigration: theme,
      );
      expect(service.active.value.id, 'default');
      expect(usingDefaultPalette, isTrue);
    });

    test('已有 palette_id -> 迁移不生效（用户自选优先）', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#112233',
        'coursePalette': <String>[
          '#9A1111',
          '#9A2222',
          '#9A3333',
          '#9A4444',
          '#9A5555',
          '#9A6666',
          '#9A7777',
          '#9A8888',
        ],
      })!;
      SharedPreferences.setMockInitialValues(<String, Object>{
        'palette_id': 'autumn',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(
        prefs,
        themeForMigration: theme,
      );
      expect(service.active.value.id, 'autumn');
      expect(activeCoursePalette, PalettePack.builtins[2].colors);
    });
  });

  group('applyFromTheme', () {
    test('带配色主题包 -> 临时包生效（theme: 前缀、不落盘）', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#112233',
        'coursePalette': <String>[
          '#9A1111',
          '#9A2222',
          '#9A3333',
          '#9A4444',
          '#9A5555',
          '#9A6666',
          '#9A7777',
          '#9A8888',
        ],
      })!;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.applyFromTheme(theme);

      expect(service.active.value.id, 'theme:${theme.id}');
      expect(activeCoursePalette, theme.coursePalette);
      // 不落盘：重建（无迁移主题）后回默认，由启动迁移逻辑负责恢复
      final PaletteService restored = PaletteService(prefs);
      expect(restored.active.value.id, 'default');
    });

    test('不带配色的主题包 -> 完全不碰调色板', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '素色',
        'seedColor': '#112233',
      })!;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.select(PalettePack.builtins[1]); // 莫兰迪
      await service.applyFromTheme(theme);

      expect(service.active.value.id, 'morandi');
      expect(activeCoursePalette, PalettePack.builtins[1].colors);
    });

    test('再选真正的配色包 -> 覆盖主题包配色', () async {
      final ThemePack theme = ThemePack.fromJson(<String, dynamic>{
        'name': '夜色',
        'seedColor': '#112233',
        'coursePalette': <String>[
          '#9A1111',
          '#9A2222',
          '#9A3333',
          '#9A4444',
          '#9A5555',
          '#9A6666',
          '#9A7777',
          '#9A8888',
        ],
      })!;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      await service.applyFromTheme(theme);
      expect(service.active.value.id, startsWith('theme:'));

      await service.select(PalettePack.builtins[2]); // 秋日
      expect(service.active.value.id, 'autumn');
      expect(activeCoursePalette, PalettePack.builtins[2].colors);

      // 用户的显式选择被持久化，重启不再被主题包配色覆盖
      final PaletteService restored = PaletteService(prefs);
      expect(restored.active.value.id, 'autumn');
    });
  });

  // ── 回归：通知监听器时的调色板状态 ─────────────────────────
  //
  // 真机踩过的 bug：select() 里先 `active.value = pack` 再
  // `setActiveCoursePalette(pack.colors)`，导致设置页的监听器
  // （_onPaletteChanged → _reapplyCourseColors）在收到通知的那一刻
  // 用 **旧调色板** 重取色，界面表现为「选中了但课块没变」。
  //
  // service 单测原先只在 select() 整体完成后断言 activeCoursePalette，
  // 看不出这个顺序问题 —— 必须从「监听器视角」断言。
  group('通知监听器时调色板必须已切换（顺序回归）', () {
    test('select -> 监听器触发时 activeCoursePalette 已是新配色', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final PalettePack custom = PalettePack.fromJson(
        jsonDecode(_custom8Json),
      )!;

      List<int>? paletteAtNotify;
      void listener() {
        // 监听方在这一刻会同步重取色 —— 此刻必须已是新调色板
        paletteAtNotify = List<int>.of(activeCoursePalette);
      }

      service.active.addListener(listener);
      await service.select(custom);
      service.active.removeListener(listener);

      expect(paletteAtNotify, isNotNull, reason: '监听器没被触发');
      expect(
        paletteAtNotify,
        custom.colors,
        reason: '通知监听器时调色板还是旧的 → 重取色会算出旧颜色',
      );
    });

    test('applyFromTheme -> 监听器触发时 activeCoursePalette 已是主题配色', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final PaletteService service = PaletteService(prefs);
      final List<int> themeColors = <int>[
        for (int i = 0; i < 8; i++) 0xFF202020 + i * 0x010101,
      ];
      final ThemePack theme = ThemePack(
        id: 't1',
        name: '测试主题',
        seedColor: 0xFF123456,
        coursePalette: themeColors,
      );

      List<int>? paletteAtNotify;
      void listener() {
        paletteAtNotify = List<int>.of(activeCoursePalette);
      }

      service.active.addListener(listener);
      await service.applyFromTheme(theme);
      service.active.removeListener(listener);

      expect(paletteAtNotify, themeColors);
    });
  });
}
