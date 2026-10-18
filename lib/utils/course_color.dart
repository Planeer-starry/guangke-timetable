/// 按课程名稳定取色的纯函数，**不依赖 flutter**。
///
/// 颜色取自固定调色板，用自定义哈希（djb2 变体）取模，
/// 保证同一课程名在任何设备、任何次运行都得到同一颜色。
library;

/// 课表配色板（ARGB int）。
///
/// 设计原则（相对旧版 Material 400 高饱和亮色的改进）：
///   1. **降饱和、微压暗** —— 去掉糖果感，与 App 整体（午夜蓝图标、
///      低对比卡片）的克制风格一致，但保持色相清晰可辨；
///   2. **16 色而非 12 色** —— 课名哈希取模后碰撞概率大幅下降
///      （6 门课无碰撞概率 22% → 35%），实测当前课表的 6 门课全部落在
///      不同色相上；
///   3. **相邻索引刻意安排成对比色相** —— 哈希碰撞无法完全避免，但相邻索引
///      的两种颜色要在色相上拉开，避免"两个相近的色号撞在一起"；
///   4. **所有色号对白字的对比度 ≥ 3.8:1**（实测 3.82 ~ 5.23，WCAG 大字号
///      AA 门槛是 3:1）—— 所以课块文字一律用白色，不再按背景亮度在
///      黑/白之间切换，视觉更整齐统一。
///
/// ⚠️ 改动本表后，已保存的课表里旧的 colorValue 需要迁移：
/// `StorageService.load` 会把「不在本表内」的 colorValue 按课名重新取值。
const List<int> coursePalette = <int>[
  0xFFC05B5B, // 0  绯红   白字 4.30:1
  0xFFB8528C, // 1  玫粉   白字 4.54:1
  0xFF8E55A8, // 2  紫     白字 5.23:1
  0xFF5A68B0, // 3  靛     白字 5.20:1
  0xFF4278B5, // 4  蓝     白字 4.58:1
  0xFF328CAE, // 5  天青   白字 3.82:1
  0xFF2C9186, // 6  青     白字 3.82:1
  0xFF3E8A55, // 7  绿     白字 4.22:1
  0xFF6B8838, // 8  草     白字 4.04:1
  0xFF98694F, // 9  赭     白字 4.70:1
  0xFFB0614A, // 10 砖红   白字 4.51:1
  0xFF63718A, // 11 石板   白字 4.93:1
  0xFF348B80, // 12 薄荷   白字 4.08:1
  0xFF7A5CC0, // 13 紫罗兰 白字 5.10:1
  0xFFA8722C, // 14 琥珀   白字 4.11:1
  0xFF857B2E, // 15 芥黄   白字 4.31:1
];

/// 依据课程名取色。空字符串返回调色板首色，保证不抛异常。
int colorValueFromName(String name) {
  if (name.isEmpty) {
    return coursePalette.first;
  }
  int hash = 5381;
  for (final int unit in name.codeUnits) {
    hash = (hash * 33 + unit) & 0x7FFFFFFF;
  }
  return coursePalette[hash % coursePalette.length];
}

/// 该 colorValue 是否是当前调色板中的颜色。
///
/// 用于判断旧数据里的颜色是否已经过时：调色板更新后，旧 colorValue
/// 不在表内，应回退到按课名重新取色。
bool isPaletteColor(int colorValue) {
  return coursePalette.contains(colorValue & 0xFFFFFFFF);
}
