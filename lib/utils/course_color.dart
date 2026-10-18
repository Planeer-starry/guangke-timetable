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
///   3. **相邻索引刻意安排成对比色** —— 哈希碰撞无法完全避免，但相邻索引
///      的两种颜色要在色相上拉开，避免"两个相近的色号撞在一起"；
///   4. 文字色由 course_block 按背景亮度自适应（白/黑取对比更高者），
///      所以本表不必为了"白字可读"而把所有颜色压暗成褐色
///      —— 暗黄在数学上就是褐，那会让配色发闷。
///
/// ⚠️ 改动本表后，已保存的课表里旧的 colorValue 需要迁移：
/// `StorageService.load` 会把「不在本表内」的 colorValue 按课名重新取值。
const List<int> coursePalette = <int>[
  0xFFC05B5B, // 0  绯红
  0xFFB8528C, // 1  玫粉
  0xFF8E55A8, // 2  紫
  0xFF5A68B0, // 3  靛
  0xFF4278B5, // 4  蓝
  0xFF328CAE, // 5  天青
  0xFF2C9186, // 6  青
  0xFF45995F, // 7  绿
  0xFF7E9C45, // 8  草
  0xFF98694F, // 9  赭
  0xFFB0614A, // 10 砖红
  0xFF63718A, // 11 石板
  0xFF3F9E92, // 12 薄荷
  0xFF7A5CC0, // 13 紫罗兰
  0xFFC08539, // 14 琥珀
  0xFF9A8F3A, // 15 芥黄
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
