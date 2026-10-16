/// 周次掩码（weekMask）的纯函数实现，**不依赖 flutter**。
///
/// 语义（AGENTS.md 5.3）：
/// 32 位整数，第 n 周有课 ⇔ 第 `(n - 1)` 位为 1，即 `1 << (n - 1)`。
/// week 从 1 开始，合法范围 1..32。
library;

/// 最小合法周次。
const int minWeek = 1;

/// 最大合法周次（32 位掩码的上限）。
const int maxWeek = 32;

/// 判断第 [week] 周是否有课。越界周次一律返回 false，不抛异常。
bool hasClassInWeek(int weekMask, int week) {
  if (week < minWeek || week > maxWeek) {
    return false;
  }
  return (weekMask & (1 << (week - 1))) != 0;
}

/// 由周次集合计算掩码，自动去重；越界周次被忽略。
int weekMaskFromWeeks(Iterable<int> weeks) {
  int mask = 0;
  for (final int week in weeks) {
    if (week < minWeek || week > maxWeek) {
      continue;
    }
    mask |= 1 << (week - 1);
  }
  return mask;
}

/// 由掩码反推有课的周次列表（升序）。
List<int> weeksFromWeekMask(int weekMask) {
  final List<int> weeks = <int>[];
  for (int week = minWeek; week <= maxWeek; week++) {
    if ((weekMask & (1 << (week - 1))) != 0) {
      weeks.add(week);
    }
  }
  return weeks;
}
