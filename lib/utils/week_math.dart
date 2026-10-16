/// 周次计算纯函数，**不依赖 flutter**。
///
/// 基准是第一周周一（[week1Monday]），周一视为一周的第一天。
/// 天数差在“仅年月日的 UTC 零点”上计算，避免时区与夏令时干扰。
library;

/// 把日期归一化为“仅年月日的 UTC 零点”。
DateTime _dateOnlyUtc(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// 计算 [date] 属于学期第几周，结果 clamp 到 `1..totalWeeks`。
///
/// 公式：`((date - week1Monday).inDays ~/ 7) + 1`。
/// 开学之前返回 1，学期结束后返回 `totalWeeks`。
int weekOfDate(DateTime date, DateTime week1Monday, int totalWeeks) {
  final int days = _dateOnlyUtc(date)
      .difference(_dateOnlyUtc(week1Monday))
      .inDays;
  final int week = (days ~/ 7) + 1;
  final int upper = totalWeeks < 1 ? 1 : totalWeeks;
  if (week < 1) {
    return 1;
  }
  if (week > upper) {
    return upper;
  }
  return week;
}

/// 返回学期第 [week] 周周一的日期（本地日期，时间部分为 00:00）。
DateTime mondayOfWeek(DateTime week1Monday, int week) {
  final DateTime monday = _dateOnlyUtc(week1Monday)
      .add(Duration(days: (week - 1) * 7));
  return DateTime(monday.year, monday.month, monday.day);
}
