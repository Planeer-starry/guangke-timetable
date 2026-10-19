import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/utils/course_color.dart';

/// 配色包导入结果：区分「成功」「失败」（与 ThemeService.ImportOutcome 同构）。
class PaletteImportOutcome {
  const PaletteImportOutcome({this.pack, this.error, this.warning});

  /// 成功导入的配色包（ok 时非 null）。
  final PalettePack? pack;

  /// 失败原因；null 表示成功。
  final String? error;

  /// 非致命提示（预留，与 ImportOutcome 保持同构）。
  final String? warning;

  bool get ok => error == null;
}

/// 课程配色服务（J7）：调色板的**唯一真相**。
///
/// J6 时调色板由 ThemePack.coursePalette 直接决定，J7 起独立：
/// - 选中配色包 / 导入 / 删除回退，active 变化即 [setActiveCoursePalette]；
/// - 主题包只在被选中且带 coursePalette 时，经 [applyFromTheme] 注入一次
///   临时包（`theme:<themeId>`），再选任何真正的配色包即覆盖；
/// - 1.3.0 老用户迁移：`palette_id` 不存在时，用构造传入的
///   [ThemePack]（当前激活主题包）的配色初始化，避免启动配色回退默认。
///
/// prefs 键：`palette_id`（String）、`palette_packs`（JSON 数组字符串）。
class PaletteService {
  PaletteService(this._prefs, {ThemePack? themeForMigration}) {
    _restore(themeForMigration);
  }

  final SharedPreferences _prefs;

  static const String _keyActiveId = 'palette_id';
  static const String _keyPacks = 'palette_packs';

  /// 当前生效配色。构造时从 prefs 恢复（含 1.3.0 迁移），找不到时回
  /// [PalettePack.fallback]。
  final ValueNotifier<PalettePack> active = ValueNotifier<PalettePack>(
    PalettePack.fallback,
  );

  /// 用户导入的配色包（不含内置；主题包临时包也不在这里）。
  final ValueNotifier<List<PalettePack>> imported =
      ValueNotifier<List<PalettePack>>(<PalettePack>[]);

  /// 全部可选配色（内置在前、导入在后；主题包临时包由 UI 层单独插入）。
  List<PalettePack> get all => <PalettePack>[
    ...PalettePack.builtins,
    ...imported.value,
  ];

  /// 选中配色并持久化；**立即应用到课程取色**。
  Future<void> select(PalettePack pack) async {
    await _prefs.setString(_keyActiveId, pack.id);
    active.value = pack;
    setActiveCoursePalette(pack.colors);
  }

  /// 从 JSON 文本导入配色包（对象或裸颜色数组），**成功即选中（立刻生效）**。
  ///
  /// 错误分层：
  /// - 非法 JSON / 顶层既不是对象也不是数组 → 解析错误；
  /// - 对象缺非空 name → 缺字段错误；
  /// - colors 无效（数量不在 8~24 / 含非法颜色）→ **直接 error**，
  ///   不允许用默认凑数——配色包的唯一内容就是颜色，颜色无效则包无意义；
  /// - id 与内置包冲突 → error（防顶掉内置定义）；
  /// - 同 id 的旧包被覆盖。
  Future<PaletteImportOutcome> importFromJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (error) {
      return PaletteImportOutcome(error: '不是有效的 JSON：$error');
    }
    if (decoded is! Map && decoded is! List) {
      return const PaletteImportOutcome(error: '配色包必须是 JSON 对象或颜色数组');
    }
    // 对象形式先单独验 name（fromJson 返回 null 无法区分原因）
    if (decoded is Map) {
      final Object? rawName = decoded['name'];
      if (rawName is! String || rawName.trim().isEmpty) {
        return const PaletteImportOutcome(error: '缺少必要字段（需要 name 和 colors）');
      }
    }
    final PalettePack? pack = PalettePack.fromJson(decoded);
    if (pack == null) {
      return const PaletteImportOutcome(error: '颜色无效（需 8~24 个颜色值）');
    }
    for (final PalettePack builtin in PalettePack.builtins) {
      if (builtin.id == pack.id) {
        return PaletteImportOutcome(
          error: '这个 id 与内置配色「${builtin.name}」冲突，请换一个 id',
        );
      }
    }
    // 同 id 覆盖，否则追加
    final List<PalettePack> next = <PalettePack>[];
    bool replaced = false;
    for (final PalettePack old in imported.value) {
      if (old.id == pack.id) {
        next.add(pack);
        replaced = true;
      } else {
        next.add(old);
      }
    }
    if (!replaced) {
      next.add(pack);
    }
    await _persistImported(next);
    await select(pack);
    return PaletteImportOutcome(pack: pack);
  }

  /// 删除导入包并持久化；内置包不可删（直接 return）。
  /// 删除后若是激活配色则回退 [PalettePack.fallback]（并应用其颜色）。
  Future<void> remove(PalettePack pack) async {
    if (pack.builtin) {
      return;
    }
    final List<PalettePack> next = <PalettePack>[
      for (final PalettePack old in imported.value)
        if (old.id != pack.id) old,
    ];
    await _persistImported(next);
    if (active.value.id == pack.id) {
      await select(PalettePack.fallback);
    }
  }

  /// 主题包带来的配色：转成临时包（`theme:<themeId>`）并应用。
  ///
  /// - 主题包不带 coursePalette → **完全不碰调色板**（J7「不绑」语义）；
  /// - 临时包**不落盘 palette_id**：落盘 `theme:xxx` 会在重启时因
  ///   byId 找不到而回退默认；不落盘 + [_restore] 的迁移逻辑
  ///   （themeForMigration）在每次启动时按当前主题包重新应用，闭环。
  ///   用户一旦选过真正的配色包（palette_id 存在），主题包配色即被覆盖；
  /// - 再 select 任何内置 / 导入配色即覆盖临时包。
  Future<void> applyFromTheme(ThemePack theme) async {
    final List<int>? colors = theme.coursePalette;
    if (colors == null) {
      return;
    }
    active.value = PalettePack(
      id: 'theme:${theme.id}',
      name: theme.name,
      colors: colors,
    );
    setActiveCoursePalette(colors);
  }

  Future<void> _persistImported(List<PalettePack> packs) async {
    imported.value = packs;
    await _prefs.setString(
      _keyPacks,
      jsonEncode(<dynamic>[
        for (final PalettePack pack in packs) pack.toJson(),
      ]),
    );
  }

  /// 构造时恢复：
  /// 1. 读导入包（损坏数据静默忽略）；
  /// 2. 按 `palette_id` 找激活配色，找不到回 fallback；
  ///    **`palette_id` 不存在**（1.3.0 升级上来、从未独立选过配色）且
  ///    迁移主题包带配色 → 用主题包配色初始化（不落盘）；
  /// 3. 最后把 active 的颜色应用到课程取色模块。
  void _restore(ThemePack? themeForMigration) {
    final List<PalettePack> packs = <PalettePack>[];
    final String? raw = _prefs.getString(_keyPacks);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? item in decoded) {
            final PalettePack? pack = PalettePack.fromJson(item);
            if (pack != null) {
              packs.add(pack);
            }
          }
        }
      } catch (_) {
        // 损坏数据：当作没有导入包，不抛异常（防御式，绝不阻断启动）
      }
    }
    imported.value = packs;

    final String? activeId = _prefs.getString(_keyActiveId);
    if (activeId != null) {
      active.value = PalettePack.byId(activeId, packs) ?? PalettePack.fallback;
    } else if (themeForMigration?.coursePalette != null) {
      final ThemePack theme = themeForMigration!;
      active.value = PalettePack(
        id: 'theme:${theme.id}',
        name: theme.name,
        colors: theme.coursePalette!,
      );
    }
    setActiveCoursePalette(active.value.colors);
  }
}
