import 'package:timetable/utils/course_color.dart';

/// 一门课程（已按连堂与周次聚合后的最终形态）。
///
/// 对应 JSON 契约 `courses[]`（见 AGENTS.md 5.2）。
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.location,
    required this.colorValue,
    required this.dayWeek,
    required this.sectionStart,
    required this.sectionEnd,
    required this.weekMask,
    this.note = '',
  });

  /// 课程唯一 id，如 `c_001`。
  final String id;

  /// 课程名称。
  final String name;

  /// 任课教师，可为空字符串。
  final String teacher;

  /// 上课地点，可为空字符串。
  final String location;

  /// 课程颜色，ARGB int。缺失时由课程名哈希稳定取色。
  final int colorValue;

  /// 星期几：1=周一 … 7=周日。
  final int dayWeek;

  /// 起始节次（闭区间）。
  final int sectionStart;

  /// 结束节次（闭区间）。
  final int sectionEnd;

  /// 周次掩码，语义见 lib/utils/week_mask.dart。
  final int weekMask;

  /// 备注。
  final String note;

  factory Course.fromJson(Map<String, dynamic> json) {
    final String name = (json['name'] as String?) ?? '';
    final Object? color = json['colorValue'];
    return Course(
      id: (json['id'] as String?) ?? '',
      name: name,
      teacher: (json['teacher'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      colorValue: color is int ? color : colorValueFromName(name),
      dayWeek: (json['dayWeek'] as int?) ?? 1,
      sectionStart: (json['sectionStart'] as int?) ?? 1,
      sectionEnd: (json['sectionEnd'] as int?) ?? 1,
      weekMask: (json['weekMask'] as int?) ?? 0,
      note: (json['note'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'teacher': teacher,
      'location': location,
      'colorValue': colorValue,
      'dayWeek': dayWeek,
      'sectionStart': sectionStart,
      'sectionEnd': sectionEnd,
      'weekMask': weekMask,
      'note': note,
    };
  }
}
