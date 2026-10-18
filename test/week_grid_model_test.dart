import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/week_grid_model.dart';

/// 2026-10-17 是周六（2026-09-07 学期的第 6 周），所在周周一 = 10-12。
final DateTime saturday = DateTime(2026, 10, 17);

TimetableData _data({
  List<Course> courses = const <Course>[],
  List<CourseOverride> overrides = const <CourseOverride>[],
}) {
  return TimetableData(
    meta: TimetableMeta(
      school: '广东科技学院',
      semesterName: '2026-2027 第一学期',
      week1Monday: DateTime(2026, 9, 7),
      totalWeeks: 20,
    ),
    periods: Period.defaults,
    courses: courses,
    overrides: overrides,
  );
}

Course _course(
  String id,
  String name,
  int dayWeek,
  int sectionStart,
  int sectionEnd, {
  int weekMask = 0xFFFFF,
  int colorValue = 4294198070,
}) {
  return Course(
    id: id,
    name: name,
    teacher: '张三',
    location: '教学楼A101',
    colorValue: colorValue,
    dayWeek: dayWeek,
    sectionStart: sectionStart,
    sectionEnd: sectionEnd,
    weekMask: weekMask,
    note: '',
  );
}

void main() {
  test('学期未配置 → 空列表', () {
    expect(weekSnapshots(TimetableData.empty(), saturday), isEmpty);
  });

  test('形状正确：3 个快照、每快照 5 行 × 7 格、行标签固定', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(_data(), saturday);
    expect(snapshots.length, 3);
    for (final WeekSnapshot s in snapshots) {
      expect(s.rows.length, 5);
      expect(s.dates.length, 7);
      for (final WeekRow row in s.rows) {
        expect(row.cells.length, 7);
      }
      expect(s.rows.map((WeekRow r) => r.label).toList(), <String>[
        '1-2',
        '3-4',
        '5-6',
        '7-8',
        '9-10',
      ]);
    }
  });

  test('3-4 节的课落在 index 1，不落在 index 0', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(courses: <Course>[_course('c_001', '计算机网络', 1, 3, 4)]),
      saturday,
    );
    final WeekSnapshot s = snapshots.first;
    expect(s.rows[0].cells[0], isNull);
    expect(s.rows[1].cells[0]?.text, '计算机网络');
    expect(s.rows[2].cells[0], isNull);
  });

  test('5-6 节的课落在 index 2', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(courses: <Course>[_course('c_001', '大学物理', 3, 5, 6)]),
      saturday,
    );
    expect(snapshots.first.rows[2].cells[2]?.text, '大学物理');
  });

  test('3-6 节的课跨 index 1 和 2（每一行都填）', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(courses: <Course>[_course('c_001', '连堂实验', 5, 3, 6)]),
      saturday,
    );
    final WeekSnapshot s = snapshots.first;
    expect(s.rows[1].cells[4]?.text, '连堂实验');
    expect(s.rows[2].cells[4]?.text, '连堂实验');
    expect(s.rows[0].cells[4], isNull);
  });

  test('同格双课 → text 是课名排序第一门、extra == 1', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(
        courses: <Course>[
          _course('c_002', '大学英语Ⅰ', 2, 1, 2),
          _course('c_001', '大学日语Ⅰ', 2, 1, 2),
        ],
      ),
      saturday,
    );
    final WeekCell? cell = snapshots.first.rows[0].cells[1];
    expect(cell, isNotNull);
    // 按 Unicode 码点排序：日(U+65E5) < 英(U+82F1)，所以「大学日语Ⅰ」排在前
    expect(cell!.text, '大学日语Ⅰ');
    expect(cell.extra, 1);
  });

  test('本周停课（cancelled override）的课不进快照', () {
    final TimetableData data = _data(
      courses: <Course>[_course('c_001', '高等数学', 6, 1, 2)],
      overrides: <CourseOverride>[
        CourseOverride(
          courseId: 'c_001',
          week: 6,
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
          location: '教学楼A101',
          cancelled: true,
        ),
      ],
    );

    final List<WeekSnapshot> snapshots = weekSnapshots(data, saturday);
    // 第 6 周周六 1-2 节：停课后该格为 null（小组件无停课态渲染）
    expect(snapshots.first.rows[0].cells[5], isNull);
  });

  test('3 个快照 weekStart 依次 +7 天，周次递增', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(_data(), saturday);
    expect(snapshots[0].weekStart, DateTime(2026, 10, 12));
    expect(snapshots[1].weekStart, DateTime(2026, 10, 19));
    expect(snapshots[2].weekStart, DateTime(2026, 10, 26));
    expect(snapshots[0].weekLabel, '第6周');
    expect(snapshots[1].weekLabel, '第7周');
    expect(snapshots[2].weekLabel, '第8周');
  });

  test('dates 格式 "M/d" 无前导零', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(_data(), saturday);
    expect(snapshots.first.dates, <String>[
      '10/12',
      '10/13',
      '10/14',
      '10/15',
      '10/16',
      '10/17',
      '10/18',
    ]);
    // 单数字月份：2026-09-07 学期的第 1 周从 9/7 开始
    final List<WeekSnapshot> september = weekSnapshots(
      _data(),
      DateTime(2026, 9, 9),
    );
    expect(september.first.dates.first, '9/7');
  });

  test('encodeList JSON 结构与 Kotlin 契约一致', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(
        courses: <Course>[
          _course('c_001', '计算机网络', 1, 3, 4),
          _course('c_002', '大学物理', 3, 5, 6),
        ],
      ),
      saturday,
    );
    final Map<String, dynamic> decoded =
        jsonDecode(weekGridsEncode(snapshots)) as Map<String, dynamic>;
    final List<dynamic> weeks = decoded['weeks'] as List<dynamic>;
    expect(weeks.length, 3);
    final Map<String, dynamic> first = weeks.first as Map<String, dynamic>;
    expect(first['weekStart'], '2026-10-12');
    expect(first['weekLabel'], '第6周');
    final List<dynamic> rows = first['rows'] as List<dynamic>;
    expect(rows.length, 5);
    final Map<String, dynamic> row1 = rows[1] as Map<String, dynamic>;
    expect(row1['label'], '3-4');
    final List<dynamic> cells = row1['cells'] as List<dynamic>;
    expect(cells[0], isNotNull);
    final Map<String, dynamic> cell = cells[0] as Map<String, dynamic>;
    expect(cell['text'], '计算机网络');
    expect(cell['color'], '4294198070'); // 字符串，Kotlin toLong 再 toInt
    expect(cell['extra'], 0);
  });

  test('weekMask 过滤：某课第 6 周有、第 7 周无', () {
    final List<WeekSnapshot> snapshots = weekSnapshots(
      _data(
        courses: <Course>[
          _course('c_001', '单周课', 1, 1, 2, weekMask: 1 << 5), // 仅第 6 周
        ],
      ),
      saturday,
    );
    expect(snapshots[0].rows[0].cells[0]?.text, '单周课');
    expect(snapshots[1].rows[0].cells[0], isNull);
  });
}
