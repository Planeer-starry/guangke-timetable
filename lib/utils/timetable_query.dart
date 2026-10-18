import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/week_mask.dart';

/// 某一周里的一次实际上课（已应用当周 override）。
class CourseOccurrence {
  const CourseOccurrence({
    required this.course,
    required this.dayWeek,
    required this.sectionStart,
    required this.sectionEnd,
    required this.location,
  });

  /// 所属课程。
  final Course course;

  /// 实际上课的星期几：1=周一 … 7=周日（已应用 override）。
  final int dayWeek;

  /// 实际起始节次（已应用 override）。
  final int sectionStart;

  /// 实际结束节次（已应用 override）。
  final int sectionEnd;

  /// 实际地点（已应用 override）。
  final String location;
}

/// 取某一周的全部上课安排。
///
/// 规则：先按 `course.weekMask` 用 `hasClassInWeek` 筛出该周有课的课程，
/// 再查 `overrides` 里有没有 `(courseId, week)` 匹配——
/// 有则用 override 的 dayWeek / sectionStart / sectionEnd / location，
/// 无则用课程自身的值。Course 模型保持不可变（编辑走 copyWith 换新实例）。
List<CourseOccurrence> coursesForWeek(TimetableData data, int week) {
  final List<CourseOccurrence> result = <CourseOccurrence>[];
  for (final Course course in data.courses) {
    if (!hasClassInWeek(course.weekMask, week)) {
      continue;
    }
    final CourseOverride? override = _overrideFor(data, course.id, week);
    result.add(
      CourseOccurrence(
        course: course,
        dayWeek: override?.dayWeek ?? course.dayWeek,
        sectionStart: override?.sectionStart ?? course.sectionStart,
        sectionEnd: override?.sectionEnd ?? course.sectionEnd,
        location: override?.location ?? course.location,
      ),
    );
  }
  return result;
}

CourseOverride? _overrideFor(TimetableData data, String courseId, int week) {
  for (final CourseOverride override in data.overrides) {
    if (override.courseId == courseId && override.week == week) {
      return override;
    }
  }
  return null;
}
