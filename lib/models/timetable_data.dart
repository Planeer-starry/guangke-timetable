import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_meta.dart';

/// 整个课表文件的顶层结构。
///
/// 对应 JSON 契约（见 AGENTS.md 5.2），字段名不可随意改动。
class TimetableData {
  const TimetableData({
    required this.meta,
    required this.periods,
    required this.courses,
    required this.overrides,
    this.schema = currentSchema,
  });

  /// 当前契约版本号。
  static const int currentSchema = 1;

  /// 契约版本号。
  final int schema;

  /// 学期元信息。
  final TimetableMeta meta;

  /// 节次作息表。
  final List<Period> periods;

  /// 课程列表。
  final List<Course> courses;

  /// 当周调课列表。
  final List<CourseOverride> overrides;

  /// 一份使用广科默认作息的空课表。
  factory TimetableData.empty() {
    return TimetableData(
      meta: TimetableMeta(
        school: '广东科技学院',
        semesterName: '',
        week1Monday: DateTime(1970, 1, 5),
        totalWeeks: 20,
      ),
      periods: Period.defaults,
      courses: <Course>[],
      overrides: <CourseOverride>[],
    );
  }

  factory TimetableData.fromJson(Map<String, dynamic> json) {
    final Object? rawPeriods = json['periods'];
    final Object? rawCourses = json['courses'];
    final Object? rawOverrides = json['overrides'];
    return TimetableData(
      schema: (json['schema'] as int?) ?? currentSchema,
      meta: TimetableMeta.fromJson(
        (json['meta'] as Map).cast<String, dynamic>(),
      ),
      periods: rawPeriods is List
          ? rawPeriods
                .map(
                  (dynamic e) =>
                      Period.fromJson((e as Map).cast<String, dynamic>()),
                )
                .toList()
          : Period.defaults,
      courses: rawCourses is List
          ? rawCourses
                .map(
                  (dynamic e) =>
                      Course.fromJson((e as Map).cast<String, dynamic>()),
                )
                .toList()
          : <Course>[],
      overrides: rawOverrides is List
          ? rawOverrides
                .map(
                  (dynamic e) => CourseOverride.fromJson(
                    (e as Map).cast<String, dynamic>(),
                  ),
                )
                .toList()
          : <CourseOverride>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schema': schema,
      'meta': meta.toJson(),
      'periods': periods.map((Period p) => p.toJson()).toList(),
      'courses': courses.map((Course c) => c.toJson()).toList(),
      'overrides': overrides.map((CourseOverride o) => o.toJson()).toList(),
    };
  }
}
