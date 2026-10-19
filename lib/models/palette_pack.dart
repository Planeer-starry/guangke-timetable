/// 课程配色包：课块调色板的纯数据描述（J7）。
///
/// J6 时调色板属于主题包（ThemePack.coursePalette），J7 起独立成包：
/// PaletteService 是调色板的**唯一真相**，主题包只在被选中时
/// 通过 `applyFromTheme` 注入一次自己的配色。
library;

import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/utils/course_color.dart';

/// 一套课块配色（8~24 个 ARGB int）。
class PalettePack {
  const PalettePack({
    required this.id,
    required this.name,
    required this.colors,
    this.builtin = false,
  });

  /// 唯一标识。内置包固定（default / morandi / autumn）；
  /// 主题包注入的临时包用 `theme:<themeId>` 前缀。
  final String id;

  /// 展示名。
  final String name;

  /// 颜色列表（ARGB int），长度 8~24。
  final List<int> colors;

  /// 是否内置包（不可删除）。
  final bool builtin;

  /// 复制并替换部分字段（J8 管理页重命名用，只改 name）。
  PalettePack copyWith({String? name}) {
    return PalettePack(
      id: id,
      name: name ?? this.name,
      colors: colors,
      builtin: builtin,
    );
  }

  /// 内置 3 套。default 直接复用 course_color.dart 的默认调色板
  /// （同一份常量，不复制）；莫兰迪 / 秋日的颜色已核算过白字对比度
  /// （最低 4.16:1，见 test/palette_contrast_test.dart 闸门），**不要自行调整**。
  static List<PalettePack> get builtins => const <PalettePack>[
    PalettePack(
      id: 'default',
      name: '默认',
      colors: defaultCoursePalette,
      builtin: true,
    ),
    PalettePack(
      id: 'morandi',
      name: '莫兰迪',
      colors: <int>[
        0xFF8C6A5D,
        0xFF6F8065,
        0xFF64788A,
        0xFF8A6A7A,
        0xFF7E7550,
        0xFF5F6E80,
        0xFF9C7362,
        0xFF74687E,
        0xFF5C7064,
        0xFF8A7448,
        0xFF7A6A74,
        0xFF62747A,
      ],
      builtin: true,
    ),
    PalettePack(
      id: 'autumn',
      name: '秋日',
      colors: <int>[
        0xFFA05A34,
        0xFF8A6B2F,
        0xFF96602E,
        0xFF7D5A3C,
        0xFF9C6B45,
        0xFF6F7A3A,
        0xFFA55A3C,
        0xFF7A4E4E,
        0xFF8A7330,
        0xFF6B5B3E,
        0xFF94572E,
        0xFF5E6B4A,
      ],
      builtin: true,
    ),
  ];

  /// 兜底（默认 16 色）。
  static PalettePack get fallback => builtins.first;

  /// 在「内置 + 导入」全体里按 id 查找；找不到返回 null。
  /// （主题包注入的临时包不在任何列表里，由调用方自行维护。）
  static PalettePack? byId(String id, Iterable<PalettePack> imported) {
    for (final PalettePack pack in builtins) {
      if (pack.id == id) {
        return pack;
      }
    }
    for (final PalettePack pack in imported) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }

  /// 序列化（导入包落盘用）。schema 供未来格式演进。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema': 1,
      'id': id,
      'name': name,
      'colors': colors,
    };
  }

  /// 防御式解析，**同时接受裸数组**：
  /// - 顶层是数组 → 当作纯颜色列表，name = `导入配色 N 色`；
  /// - 顶层是对象 → 必须有非空 name + 可解析 colors；
  /// - 任一不满足 → null。
  static PalettePack? fromJson(Object? json) {
    if (json is List) {
      final List<int>? colors = parseColors(json);
      if (colors == null) {
        return null;
      }
      final String name = '导入配色 ${colors.length} 色';
      return PalettePack(
        id: 'imported_${name.hashCode.toRadixString(16)}',
        name: name,
        colors: colors,
      );
    }
    if (json is! Map) {
      return null;
    }
    // 手动收键：Map 的键可能不是 String，cast() 是懒转型、访问才抛
    final Map<String, dynamic> map = <String, dynamic>{};
    json.forEach((Object? key, Object? value) {
      if (key is String) {
        map[key] = value;
      }
    });
    final Object? rawName = map['name'];
    if (rawName is! String || rawName.trim().isEmpty) {
      return null;
    }
    final String name = rawName.trim();
    final List<int>? colors = parseColors(map['colors']);
    if (colors == null) {
      return null;
    }
    final Object? rawId = map['id'];
    final String id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : 'imported_${name.hashCode.toRadixString(16)}';
    return PalettePack(id: id, name: name, colors: colors, builtin: false);
  }

  /// 解析颜色列表：必须是数组、每个元素都能解析成颜色
  /// （复用 [ThemePack.parseColor] 规则）、且长度在 8~24 之间；
  /// 否则 null。
  static List<int>? parseColors(Object? raw) {
    if (raw is! List || raw.length < 8 || raw.length > 24) {
      return null;
    }
    final List<int> colors = <int>[];
    for (final Object? item in raw) {
      final int? color = ThemePack.parseColor(item);
      if (color == null) {
        return null;
      }
      colors.add(color);
    }
    return colors;
  }

  /// 值语义：**所有字段都相等**才算相等（id / name / builtin / colors 逐元素）。
  ///
  /// ⚠️ 不能只按 id 判等（J6 教训）：PaletteService 用
  /// `ValueNotifier<PalettePack>` 承载 active，`ValueNotifier.value` 的
  /// setter 在 `==` 相等时**跳过赋值、不通知监听者**——只比 id 会让
  /// 「同 id 覆盖（改了颜色）」被当成没变，界面静默不刷新。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PalettePack &&
        other.id == id &&
        other.name == name &&
        other.builtin == builtin &&
        _sameColors(other.colors, colors);
  }

  @override
  int get hashCode => Object.hash(id, name, builtin, Object.hashAll(colors));

  /// 两个颜色列表是否逐元素相同。
  static bool _sameColors(List<int> a, List<int> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
