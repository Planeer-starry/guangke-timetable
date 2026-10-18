import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/timetable_data.dart';

/// 课表编辑的纯逻辑（新增 / 替换 / 删除课程），不依赖 Flutter，可单测。
///
/// 约定：页面不直接改 storage，调用方拿到返回的新 [TimetableData]
/// 后自行持久化（与 semester_setup_screen 的返回模式一致）。
class CourseEditor {
  /// 新增或替换课程（按 id 匹配：id 已存在则原位替换，否则追加）。
  static TimetableData upsertCourse(TimetableData data, Course course) {
    final List<Course> next = <Course>[];
    bool replaced = false;
    for (final Course existing in data.courses) {
      if (existing.id == course.id) {
        next.add(course);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.add(course);
    }
    return data.copyWith(courses: next);
  }

  /// 删除课程，**同时删除该课程的所有 overrides**
  /// （否则留下引用不存在课程的悬空记录）。
  static TimetableData deleteCourse(TimetableData data, String courseId) {
    return data.copyWith(
      courses: data.courses.where((Course c) => c.id != courseId).toList(),
      overrides: data.overrides
          .where((CourseOverride o) => o.courseId != courseId)
          .toList(),
    );
  }

  /// 生成新的手动课程 id：`u_NNN`（三位补零，超出自然进位）。
  ///
  /// 手动课用 `u_` 前缀，与导入课的 `c_` / `jw_` 区开；
  /// 取现有 `u_` 编号最大值 +1，保证不与已有 id 冲突。
  static String newCourseId(TimetableData data) {
    int max = 0;
    final RegExp pattern = RegExp(r'^u_(\d+)$');
    for (final Course course in data.courses) {
      final RegExpMatch? match = pattern.firstMatch(course.id);
      if (match == null) {
        continue;
      }
      final int n = int.tryParse(match.group(1)!) ?? 0;
      if (n > max) {
        max = n;
      }
    }
    return 'u_${(max + 1).toString().padLeft(3, '0')}';
  }

  /// 为某门课的某一周设置临时调整（override）。
  ///
  /// 按 `(courseId, week)` 匹配：已存在则**原位替换**，
  /// 保证同一门课同一周只有一条调整，不会重复堆积；不存在则追加。
  static TimetableData setOverride(
    TimetableData data,
    CourseOverride override,
  ) {
    bool replaced = false;
    final List<CourseOverride> next = <CourseOverride>[];
    for (final CourseOverride existing in data.overrides) {
      final bool sameKey =
          existing.courseId == override.courseId &&
          existing.week == override.week;
      if (sameKey) {
        next.add(override);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) {
      next.add(override);
    }
    return data.copyWith(overrides: next);
  }

  /// 删除某门课某一周的 override（「取消本周调整」）。
  ///
  /// 按 `(courseId, week)` 匹配删除——停课（cancelled）与改时间地点
  /// 共用同一条 override，一删全删，课程恢复原始时间地点；
  /// 没有匹配记录时原样返回。
  static TimetableData removeOverride(
    TimetableData data,
    String courseId,
    int week,
  ) {
    return data.copyWith(
      overrides: data.overrides
          .where(
            (CourseOverride o) => !(o.courseId == courseId && o.week == week),
          )
          .toList(),
    );
  }

  /// 找出同名的所有课程（用于批量删除前的确认与展示）。
  ///
  /// 名称比较用 **trim 后完全相等**，不做模糊匹配——
  /// 避免「高等数学BⅠ」误删「高等数学BⅡ」。
  static List<Course> coursesNamed(TimetableData data, String name) {
    final String trimmed = name.trim();
    return data.courses.where((Course c) => c.name.trim() == trimmed).toList();
  }

  /// 删除所有同名课程，并连带清理它们的 overrides。
  ///
  /// 没有同名课程时原样返回。
  static TimetableData deleteCoursesNamed(TimetableData data, String name) {
    final Set<String> ids = coursesNamed(
      data,
      name,
    ).map((Course c) => c.id).toSet();
    if (ids.isEmpty) {
      return data;
    }
    return data.copyWith(
      courses: data.courses.where((Course c) => !ids.contains(c.id)).toList(),
      overrides: data.overrides
          .where((CourseOverride o) => !ids.contains(o.courseId))
          .toList(),
    );
  }
}
