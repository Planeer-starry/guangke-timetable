/// 课表的学期元信息。
///
/// 对应 JSON 契约 `meta`（见 AGENTS.md 5.2）。
class TimetableMeta {
  const TimetableMeta({
    required this.school,
    required this.semesterName,
    required this.week1Monday,
    required this.totalWeeks,
  });

  /// 学校名称。
  final String school;

  /// 学期名称，如 `2026-2027 第一学期`。
  final String semesterName;

  /// 第一周周一的日期（本地日期，时间部分为 00:00）。
  final DateTime week1Monday;

  /// 学期总周数。
  final int totalWeeks;

  factory TimetableMeta.fromJson(Map<String, dynamic> json) {
    // 防御式：字段缺失或日期非法时不抛异常，回退到「学期未设置」。
    // 年 ≤ 1 视为未设置（避免本地/UTC 时区差异把哨兵值比成已配置）。
    final DateTime? parsed = DateTime.tryParse('${json['week1Monday'] ?? ''}');
    return TimetableMeta(
      school: (json['school'] as String?) ?? '',
      semesterName: (json['semesterName'] as String?) ?? '',
      week1Monday: (parsed == null || parsed.year <= 1)
          ? DateTime.utc(1, 1, 1)
          : parsed,
      totalWeeks: (json['totalWeeks'] as int?) ?? 20,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'school': school,
      'semesterName': semesterName,
      'week1Monday': _formatDate(week1Monday),
      'totalWeeks': totalWeeks,
    };
  }

  /// 把日期格式化为 `yyyy-MM-dd`（不依赖 intl，保证纯逻辑可单测）。
  static String _formatDate(DateTime date) {
    final String y = date.year.toString().padLeft(4, '0');
    final String m = date.month.toString().padLeft(2, '0');
    final String d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
