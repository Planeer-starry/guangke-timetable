import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/timetable_exporter.dart';
import 'package:timetable/utils/timetable_importer.dart';

/// 导出纯函数（J11）：五键齐全 + 往返一致 + 可被 importer 当作备份导入。

TimetableData _sample() {
  return TimetableData(
    meta: TimetableMeta(
      school: '广东科技学院',
      semesterName: '2026-2027 第一学期',
      week1Monday: DateTime(2026, 9, 7),
      totalWeeks: 20,
    ),
    periods: const <Period>[
      Period(index: 1, start: '08:30', end: '09:15'),
      Period(index: 2, start: '09:20', end: '10:05'),
    ],
    courses: const <Course>[
      Course(
        id: 'c_001',
        name: '计算机网络',
        teacher: '张三',
        location: '教学楼A101',
        colorValue: 4294198070,
        dayWeek: 1,
        sectionStart: 3,
        sectionEnd: 4,
        weekMask: 65535,
        note: '',
      ),
    ],
    overrides: const <CourseOverride>[
      CourseOverride(
        courseId: 'c_001',
        week: 8,
        dayWeek: 3,
        sectionStart: 5,
        sectionEnd: 6,
        location: '实验楼B203',
        cancelled: true,
      ),
    ],
  );
}

void main() {
  test('导出包含 schema / meta / periods / courses / overrides 五个顶层键', () {
    final Map<String, dynamic> decoded =
        jsonDecode(exportTimetableJson(_sample())) as Map<String, dynamic>;

    expect(
      decoded.keys,
      containsAll(<String>[
        'schema',
        'meta',
        'periods',
        'courses',
        'overrides',
      ]),
    );
    expect((decoded['courses'] as List<dynamic>).length, 1);
    expect((decoded['overrides'] as List<dynamic>).length, 1);
    expect((decoded['periods'] as List<dynamic>).length, 2);
  });

  test('导出 → fromJson 往返：各字段一致（含 overrides 与自定义 periods）', () {
    final TimetableData original = _sample();
    final String json = exportTimetableJson(original);
    final Map<String, dynamic> decoded =
        jsonDecode(json) as Map<String, dynamic>;
    final TimetableData restored = TimetableData.fromJson(decoded);

    expect(restored.meta.school, original.meta.school);
    expect(restored.meta.semesterName, original.meta.semesterName);
    expect(restored.meta.week1Monday, original.meta.week1Monday);
    expect(restored.meta.totalWeeks, original.meta.totalWeeks);
    expect(restored.periods.length, 2);
    expect(restored.periods[1].start, '09:20');
    expect(restored.courses.single.name, '计算机网络');
    expect(restored.courses.single.sectionStart, 3);
    expect(restored.courses.single.weekMask, 65535);
    expect(restored.overrides.single.courseId, 'c_001');
    expect(restored.overrides.single.location, '实验楼B203');
    expect(restored.overrides.single.cancelled, isTrue);
  });

  test('导出的 JSON 能被 parseImportedTimetable 当作 App 备份完整导入', () {
    final Map<String, dynamic> decoded =
        jsonDecode(exportTimetableJson(_sample())) as Map<String, dynamic>;
    final ImportResult imported = parseImportedTimetable(decoded);

    expect(imported.error, isNull);
    expect(imported.courses.single.name, '计算机网络');
    expect(imported.courses.single.id, 'c_001');
    expect(imported.meta, isNotNull);
    expect(imported.meta!.week1Monday, DateTime(2026, 9, 7));
    expect(imported.periods, isNotNull);
    expect(imported.periods!.length, 2);
    expect(imported.overrides, isNotNull);
    expect(imported.overrides!.single.courseId, 'c_001');
    expect(imported.overrides!.single.cancelled, isTrue);
  });
}
