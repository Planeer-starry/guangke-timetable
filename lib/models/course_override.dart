/// 当周调整：某一门课在某一周被临时改到其它时间或地点，
/// 或被标记为停课（[cancelled]）。
///
/// 对应 JSON 契约 `overrides[]`（见 AGENTS.md 5.2）。
class CourseOverride {
  const CourseOverride({
    required this.courseId,
    required this.week,
    required this.dayWeek,
    required this.sectionStart,
    required this.sectionEnd,
    required this.location,
    this.cancelled = false,
  });

  /// 关联的课程 id。
  final String courseId;

  /// 生效周次，从 1 开始。
  final int week;

  /// 调整后的星期几：1=周一 … 7=周日。
  final int dayWeek;

  /// 调整后的起始节次（闭区间）。
  final int sectionStart;

  /// 调整后的结束节次（闭区间）。
  final int sectionEnd;

  /// 调整后的上课地点。
  final String location;

  /// 该周是否停课（true = 本周停课，不参与实际上课）。
  final bool cancelled;

  factory CourseOverride.fromJson(Map<String, dynamic> json) {
    return CourseOverride(
      courseId: (json['courseId'] as String?) ?? '',
      week: (json['week'] as int?) ?? 0,
      dayWeek: (json['dayWeek'] as int?) ?? 1,
      sectionStart: (json['sectionStart'] as int?) ?? 1,
      sectionEnd: (json['sectionEnd'] as int?) ?? 1,
      location: (json['location'] as String?) ?? '',
      // 旧数据没有该字段 → 视为未停课（向后兼容）
      cancelled: (json['cancelled'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'courseId': courseId,
      'week': week,
      'dayWeek': dayWeek,
      'sectionStart': sectionStart,
      'sectionEnd': sectionEnd,
      'location': location,
      'cancelled': cancelled,
    };
  }
}
