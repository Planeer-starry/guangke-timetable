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

  /// 学期开始日「未设置」时的哨兵值。
  ///
  /// ⚠️ 它**不是真实学期**：当 `meta.week1Monday` 等于它时，表示学期还没配置
  /// （见 [semesterConfigured]）。此时**不要**用 week_math.weekOfDate 计算周次，
  /// 结果没有意义。
  ///
  /// **UI 层必须先让用户设置「第一周周一」并写回 `meta.week1Monday`，
  /// 之后才能计算、展示周次。**
  static final DateTime unsetWeek1Monday = DateTime.utc(1, 1, 1);

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

  /// 学期开始日是否已由用户设置。未设置时不得计算、展示周次。
  bool get semesterConfigured => meta.week1Monday != unsetWeek1Monday;

  /// 一份使用广科默认作息、但学期尚未设置的空课表。
  factory TimetableData.empty() {
    return TimetableData(
      meta: _unsetMeta(),
      periods: Period.defaults,
      courses: <Course>[],
      overrides: <CourseOverride>[],
    );
  }

  /// 防御式解析：任何字段缺失或类型不符都回退到默认值，绝不抛异常
  /// （见 AGENTS.md 5.1）。
  factory TimetableData.fromJson(Map<String, dynamic> json) {
    final List<Period> periods = _parseList<Period>(
      json['periods'],
      Period.fromJson,
    );
    return TimetableData(
      schema: (json['schema'] as int?) ?? currentSchema,
      meta: _parseMeta(json['meta']),
      periods: periods.isEmpty ? Period.defaults : periods,
      courses: _parseList<Course>(json['courses'], Course.fromJson),
      overrides: _parseList<CourseOverride>(
        json['overrides'],
        CourseOverride.fromJson,
      ),
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

  /// 「学期未设置」的元信息：周次基准取 [unsetWeek1Monday]。
  static TimetableMeta _unsetMeta() {
    return TimetableMeta(
      school: '',
      semesterName: '',
      week1Monday: unsetWeek1Monday,
      totalWeeks: 20,
    );
  }

  /// 防御式解析 meta：缺失时回退到「学期未设置」，日期解析失败同样回退。
  static TimetableMeta _parseMeta(Object? raw) {
    if (raw is! Map) {
      return _unsetMeta();
    }
    final Map<String, dynamic> map = raw.cast<String, dynamic>();
    final Object? rawWeek1 = map['week1Monday'];
    final DateTime week1Monday;
    if (rawWeek1 is DateTime) {
      week1Monday = rawWeek1;
    } else if (rawWeek1 is String) {
      week1Monday = DateTime.tryParse(rawWeek1) ?? unsetWeek1Monday;
    } else {
      week1Monday = unsetWeek1Monday;
    }
    return TimetableMeta(
      school: (map['school'] as String?) ?? '',
      semesterName: (map['semesterName'] as String?) ?? '',
      week1Monday: week1Monday,
      totalWeeks: (map['totalWeeks'] as int?) ?? 20,
    );
  }

  /// 防御式解析列表：非 List 返回空表；元素不是 Map 时跳过，绝不抛异常。
  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    if (raw is! List) {
      return <T>[];
    }
    final List<T> result = <T>[];
    for (final Object? item in raw) {
      if (item is Map) {
        result.add(fromJson(item.cast<String, dynamic>()));
      }
    }
    return result;
  }
}
