import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:timetable/models/theme_pack.dart';

/// 主题包导入结果：区分「成功」「成功但配色被忽略」「失败」。
class ImportOutcome {
  const ImportOutcome({this.pack, this.error, this.warning});

  /// 成功导入的主题包（ok 时非 null）。
  final ThemePack? pack;

  /// 失败原因；null 表示成功。
  final String? error;

  /// 非致命提示（如课程配色无效已忽略，改用默认）。
  final String? warning;

  bool get ok => error == null;
}

/// 主题包服务：管理激活主题与导入主题包（shared_preferences 持久化）。
///
/// prefs 键：
/// - `theme_pack_id`（String）：激活主题 id；
/// - `theme_packs`（JSON 数组字符串）：导入的主题包。
///
/// ⚠️ 只存 UI 偏好（选了哪套外观），不涉及学期参数，符合 AGENTS.md 5.1。
class ThemeService {
  ThemeService(this._prefs) {
    _restore();
  }

  final SharedPreferences _prefs;

  static const String _keyActiveId = 'theme_pack_id';
  static const String _keyPacks = 'theme_packs';

  /// 当前生效主题。构造时从 prefs 恢复，找不到时回 [ThemePack.fallback]。
  final ValueNotifier<ThemePack> active = ValueNotifier<ThemePack>(
    ThemePack.fallback,
  );

  /// 用户导入的主题包（不含内置）。
  final ValueNotifier<List<ThemePack>> imported =
      ValueNotifier<List<ThemePack>>(<ThemePack>[]);

  /// 全部可选主题（内置在前、导入在后）。
  List<ThemePack> get all => <ThemePack>[
    ...ThemePack.builtins,
    ...imported.value,
  ];

  /// 选中主题并持久化（id 落盘，重启后恢复）。
  Future<void> select(ThemePack pack) async {
    await _prefs.setString(_keyActiveId, pack.id);
    active.value = pack;
  }

  /// 从 JSON 文本导入主题包，**成功即选中（立刻生效）**。
  ///
  /// - 非法 JSON / 顶层不是对象 / 缺必填字段 → error；
  /// - id 与内置包冲突 → error（防止导入包顶掉内置定义）；
  /// - coursePalette 给了但无效 → 仍导入，warning 告知「已使用默认」
  ///   （宽容策略：外观主体是种子色，配色无效不值得整个拒绝）；
  /// - 同 id 的旧包被覆盖。
  Future<ImportOutcome> importFromJson(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (error) {
      return ImportOutcome(error: '不是有效的 JSON：$error');
    }
    if (decoded is! Map) {
      return const ImportOutcome(error: '主题包必须是 JSON 对象');
    }
    final ThemePack? pack = ThemePack.fromJson(decoded);
    if (pack == null) {
      return const ImportOutcome(error: '缺少必要字段（需要 name 和 seedColor）');
    }
    for (final ThemePack builtin in ThemePack.builtins) {
      if (builtin.id == pack.id) {
        return ImportOutcome(error: '这个 id 与内置主题包「${builtin.name}」冲突，请换一个 id');
      }
    }
    String? warning;
    if (decoded['coursePalette'] != null && pack.coursePalette == null) {
      warning = '课程配色无效（需 8~24 个颜色），已使用默认';
    }
    // 同 id 覆盖，否则追加
    final List<ThemePack> next = <ThemePack>[];
    bool replaced = false;
    for (final ThemePack old in imported.value) {
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
    return ImportOutcome(pack: pack, warning: warning);
  }

  /// 删除导入包并持久化；内置包不可删（直接 return）。
  /// 删除后若是激活主题则回退 [ThemePack.fallback]。
  Future<void> remove(ThemePack pack) async {
    if (pack.builtin) {
      return;
    }
    final List<ThemePack> next = <ThemePack>[
      for (final ThemePack old in imported.value)
        if (old.id != pack.id) old,
    ];
    await _persistImported(next);
    if (active.value.id == pack.id) {
      await select(ThemePack.fallback);
    }
  }

  Future<void> _persistImported(List<ThemePack> packs) async {
    imported.value = packs;
    await _prefs.setString(
      _keyPacks,
      jsonEncode(<dynamic>[for (final ThemePack pack in packs) pack.toJson()]),
    );
  }

  /// 构造时恢复：先读导入包（损坏数据静默忽略），再按 id 找激活主题。
  void _restore() {
    final List<ThemePack> packs = <ThemePack>[];
    final String? raw = _prefs.getString(_keyPacks);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? item in decoded) {
            final ThemePack? pack = ThemePack.fromJson(item);
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
      active.value = ThemePack.byId(activeId, packs) ?? ThemePack.fallback;
    }
  }
}
