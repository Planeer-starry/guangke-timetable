import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/theme_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThemeService', () {
    test('默认 active == fallback，imported 为空', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      expect(service.active.value.id, ThemePack.fallback.id);
      expect(service.imported.value, isEmpty);
      expect(service.all, hasLength(6));
    });

    test('select 持久化：重建 service 仍是它', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      await service.select(ThemePack.builtins[1]);
      expect(service.active.value.id, 'forest');

      final ThemeService restored = ThemeService(prefs);
      expect(restored.active.value.id, 'forest');
    });

    test('导入合法主题包 -> ok、立刻生效、持久化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson(
        '{"name":"夜色","seedColor":"#123456"}',
      );
      expect(outcome.ok, isTrue);
      expect(outcome.error, isNull);
      expect(outcome.warning, isNull);
      expect(outcome.pack, isNotNull);
      expect(service.imported.value, hasLength(1));
      expect(service.active.value.id, outcome.pack!.id);
      expect(service.active.value.seedColor, 0xFF123456);
      expect(service.all, hasLength(7));

      final ThemeService restored = ThemeService(prefs);
      expect(restored.imported.value, hasLength(1));
      expect(restored.active.value.id, outcome.pack!.id);
    });

    test('同 id 导入 -> 覆盖旧包', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      await service.importFromJson(
        '{"id":"night","name":"夜色","seedColor":"#111111"}',
      );
      final ImportOutcome second = await service.importFromJson(
        '{"id":"night","name":"夜色改","seedColor":"#222222"}',
      );
      expect(second.ok, isTrue);
      expect(service.imported.value, hasLength(1));
      expect(service.active.value.seedColor, 0xFF222222);
      expect(service.active.value.name, '夜色改');
    });

    test('非法 JSON -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson('这不是json');
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('不是有效的 JSON'));
      expect(service.imported.value, isEmpty);
    });

    test('顶层不是对象 -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson('[1,2]');
      expect(outcome.error, '主题包必须是 JSON 对象');
    });

    test('缺 name / 缺 seedColor -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome noName = await service.importFromJson(
        '{"seedColor":"#112233"}',
      );
      expect(noName.error, '缺少必要字段（需要 name 和 seedColor）');
      final ImportOutcome noSeed = await service.importFromJson(
        '{"name":"夜色"}',
      );
      expect(noSeed.error, '缺少必要字段（需要 name 和 seedColor）');
    });

    test('id 与内置包冲突 -> error', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson(
        '{"id":"indigo","name":"假靛蓝","seedColor":"#111111"}',
      );
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('内置主题包「靛蓝」'));
      expect(service.imported.value, isEmpty);
    });

    test('带无效 coursePalette -> ok + warning', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233","coursePalette":["#FF0000"]}',
      );
      expect(outcome.ok, isTrue);
      expect(outcome.warning, contains('课程配色无效'));
      expect(outcome.pack!.coursePalette, isNull);
      // 包仍导入且生效
      expect(service.imported.value, hasLength(1));
      expect(service.active.value.seedColor, 0xFF112233);
    });

    test('remove 导入包 -> imported 清空', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233"}',
      );
      await service.select(ThemePack.builtins[2]);
      await service.remove(outcome.pack!);
      expect(service.imported.value, isEmpty);
      expect(service.active.value.id, 'crimson');

      final ThemeService restored = ThemeService(prefs);
      expect(restored.imported.value, isEmpty);
    });

    test('remove 正在用的包 -> active 回退 fallback', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      final ImportOutcome outcome = await service.importFromJson(
        '{"name":"夜色","seedColor":"#112233"}',
      );
      expect(service.active.value.id, outcome.pack!.id);
      await service.remove(outcome.pack!);
      expect(service.active.value.id, ThemePack.fallback.id);
      expect(service.imported.value, isEmpty);

      final ThemeService restored = ThemeService(prefs);
      expect(restored.active.value.id, 'indigo');
    });

    test('remove 内置包 -> 无变化', () async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      await service.select(ThemePack.builtins[1]);
      await service.remove(ThemePack.builtins[1]);
      expect(service.active.value.id, 'forest');
      expect(service.imported.value, isEmpty);
      expect(service.all, hasLength(6));
    });

    test('预置损坏的 theme_packs -> 不抛、imported 为空', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_packs': '{{{不是json',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      expect(service.imported.value, isEmpty);
      expect(service.active.value.id, 'indigo');
    });

    test('预置 theme_packs 混入垃圾元素 -> 只留合法项', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'theme_packs':
            '[{"name":"好的","seedColor":"#112233"}, 42, null, "x", '
            '{"name":"","seedColor":"#112233"}]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeService service = ThemeService(prefs);
      expect(service.imported.value, hasLength(1));
      expect(service.imported.value.single.name, '好的');
    });
  });
}
