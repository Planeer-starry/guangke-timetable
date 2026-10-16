/// 按课程名稳定取色的纯函数，**不依赖 flutter**。
///
/// 颜色取自固定调色板，用自定义哈希（djb2 变体）取模，
/// 保证同一课程名在任何设备、任何次运行都得到同一颜色。
library;

/// 课表配色板（ARGB int）。
const List<int> coursePalette = <int>[
  0xFFEF5350, // 红
  0xFFEC407A, // 粉
  0xFFAB47BC, // 紫
  0xFF7E57C2, // 深紫
  0xFF5C6BC0, // 靛蓝
  0xFF42A5F5, // 蓝
  0xFF29B6F6, // 浅蓝
  0xFF26A69A, // 青
  0xFF66BB6A, // 绿
  0xFF9CCC65, // 浅绿
  0xFFFFA726, // 橙
  0xFF8D6E63, // 棕
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
