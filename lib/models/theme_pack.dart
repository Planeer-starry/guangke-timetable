/// 主题包：整套外观的纯数据描述（配置驱动，J6 设计）。
///
/// Flutter 移动端 AOT 编译、无运行时解释器，扩展点做成**数据**：
/// 一个 JSON 描述界面种子色 + 课程调色板 + 小组件强调色，可导入、
/// 可分享、零风险。
///
/// 小组件的技术边界（如实告知用户）：卡片背景色 / 文字色**不跟随**
/// （RemoteViews 无法设置程序化创建的圆角 Drawable，改纯色会丢圆角，
/// 文字跟着变有对比度风险）；今日列高亮 / 下节课色条（widgetAccent）
/// 与课程色块（颜色由 Dart 算好经 JSON 传给 Kotlin）**跟随**。
library;

/// 一套主题外观（界面配色 + 课程配色 + 小组件强调色）。
class ThemePack {
  const ThemePack({
    required this.id,
    required this.name,
    required this.seedColor,
    this.coursePalette,
    this.widgetAccent,
    this.builtin = false,
  });

  /// 唯一标识。内置包固定（indigo / forest / …），导入包不可占用；
  /// 导入包缺省时由 [fromJson] 按 name 派生并固化到落盘 JSON。
  final String id;

  /// 展示名。
  final String name;

  /// 界面种子色（ARGB int），`ColorScheme.fromSeed` 的输入。
  final int seedColor;

  /// 课程调色板（ARGB int 列表）；null = 用内置默认 16 色。
  final List<int>? coursePalette;

  /// 小组件强调色；null = 取 [seedColor]。
  final int? widgetAccent;

  /// 是否内置包（不可删除）。
  final bool builtin;

  /// 复制并替换部分字段（J8 管理页重命名用，只改 name）。
  ThemePack copyWith({String? name}) {
    return ThemePack(
      id: id,
      name: name ?? this.name,
      seedColor: seedColor,
      coursePalette: coursePalette,
      widgetAccent: widgetAccent,
      builtin: builtin,
    );
  }

  /// 内置 6 套。种子色取自课程调色板的雅致色，与课表观感统一；
  /// 都不带 coursePalette（用默认 16 色），widgetAccent 也为 null。
  static List<ThemePack> get builtins => const <ThemePack>[
    ThemePack(id: 'indigo', name: '靛蓝', seedColor: 0xFF3F51B5, builtin: true),
    ThemePack(id: 'forest', name: '墨绿', seedColor: 0xFF35754F, builtin: true),
    ThemePack(id: 'crimson', name: '绛红', seedColor: 0xFF9E4B4B, builtin: true),
    ThemePack(id: 'amber', name: '琥珀', seedColor: 0xFFA8712F, builtin: true),
    ThemePack(id: 'slate', name: '石板', seedColor: 0xFF5A6880, builtin: true),
    ThemePack(id: 'violet', name: '紫罗兰', seedColor: 0xFF7A5CC0, builtin: true),
  ];

  /// 兜底（默认）主题包 = 靛蓝。
  static ThemePack get fallback => builtins.first;

  /// 在「内置 + 导入」全体里按 id 查找；找不到返回 null。
  static ThemePack? byId(String id, Iterable<ThemePack> imported) {
    for (final ThemePack pack in builtins) {
      if (pack.id == id) {
        return pack;
      }
    }
    for (final ThemePack pack in imported) {
      if (pack.id == id) {
        return pack;
      }
    }
    return null;
  }

  /// 序列化（导入包落盘用）。builtin 是运行时概念，不参与序列化。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'seedColor': seedColor,
      if (coursePalette != null) 'coursePalette': coursePalette,
      if (widgetAccent != null) 'widgetAccent': widgetAccent,
    };
  }

  /// 防御式解析：任何字段缺失或非法都返回 null / 置空，绝不抛异常。
  ///
  /// - 必填：name 非空字符串、seedColor 可 [parseColor]；
  /// - id 缺省 → `'imported_' + name.hashCode.toRadixString(16)`
  ///   （落盘时固化，重启不会漂移）；
  /// - coursePalette / widgetAccent 无效 → 置 null（宽容策略：
  ///   包仍可导入，只是忽略配色部分，由调用方告知用户）；
  /// - builtin 强制 false（内置包不走 JSON）。
  static ThemePack? fromJson(Object? json) {
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
    final int? seedColor = parseColor(map['seedColor']);
    if (seedColor == null) {
      return null;
    }
    final Object? rawId = map['id'];
    final String id = rawId is String && rawId.trim().isNotEmpty
        ? rawId.trim()
        : 'imported_${name.hashCode.toRadixString(16)}';
    return ThemePack(
      id: id,
      name: name,
      seedColor: seedColor,
      coursePalette: parsePalette(map['coursePalette']),
      widgetAccent: parseColor(map['widgetAccent']),
      builtin: false,
    );
  }

  /// 解析颜色（ARGB int）：
  /// - int 且 `0 < v <= 0xFFFFFFFF` → 原值；
  /// - `"#RRGGBB"` → 补不透明 FF；
  /// - `"#AARRGGBB"` → 原值；
  /// - 其它（null / 位数不对 / 缺 `#` / 0 / 负数 / 超范围）→ null。
  static int? parseColor(Object? raw) {
    if (raw is int) {
      return (raw > 0 && raw <= 0xFFFFFFFF) ? raw : null;
    }
    if (raw is String) {
      final String text = raw.trim();
      if (text.length == 7 && text.startsWith('#')) {
        final int? rgb = int.tryParse(text.substring(1), radix: 16);
        if (rgb != null && rgb > 0) {
          return 0xFF000000 | rgb;
        }
      }
      if (text.length == 9 && text.startsWith('#')) {
        final int? argb = int.tryParse(text.substring(1), radix: 16);
        if (argb != null && argb > 0) {
          return argb;
        }
      }
    }
    return null;
  }

  /// 解析课程调色板：必须是数组、每个元素都能 [parseColor]、
  /// 且长度在 8~24 之间；否则 null（= 用默认调色板，不报错）。
  static List<int>? parsePalette(Object? raw) {
    if (raw is! List || raw.length < 8 || raw.length > 24) {
      return null;
    }
    final List<int> colors = <int>[];
    for (final Object? item in raw) {
      final int? color = parseColor(item);
      if (color == null) {
        return null;
      }
      colors.add(color);
    }
    return colors;
  }

  /// 值语义：**所有字段都相等**才算相等。
  ///
  /// ⚠️ 不能只按 id 判等。`ThemeService` 用 `ValueNotifier<ThemePack>` 承载
  /// 当前主题包，而 `ValueNotifier.value` 的 setter 是
  /// `if (_value == newValue) return;` —— 相等就**跳过赋值、不通知监听者**。
  /// 若只比 id，那么「同 id 导入覆盖」（改颜色 / 改课程配色）会被当成没变，
  /// 界面和小组件都不会刷新。这条被 `theme_service_test` 的
  /// 「同 id 导入 -> 覆盖旧包」用例抓到过。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ThemePack &&
        other.id == id &&
        other.name == name &&
        other.seedColor == seedColor &&
        other.builtin == builtin &&
        other.widgetAccent == widgetAccent &&
        _sameColors(other.coursePalette, coursePalette);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    seedColor,
    builtin,
    widgetAccent,
    coursePalette == null ? null : Object.hashAll(coursePalette!),
  );

  /// 两个可选调色板是否逐元素相同（含 null 情形）。
  static bool _sameColors(List<int>? a, List<int>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
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
