import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/today_classes.dart';

/// 2026-09-07 学期的第 6 周周六（与规格样例「10月17日 周六 · 第6周」一致）。
final DateTime saturday = DateTime(2026, 10, 17);

TimetableData _data({
  List<Course> courses = const <Course>[],
  List<CourseOverride> overrides = const <CourseOverride>[],
  DateTime? week1Monday,
}) {
  return TimetableData(
    meta: TimetableMeta(
      school: '广东科技学院',
      semesterName: '2026-2027 第一学期',
      week1Monday: week1Monday ?? DateTime(2026, 9, 7),
      totalWeeks: 20,
    ),
    periods: Period.defaults,
    courses: courses,
    overrides: overrides,
  );
}

Course _course({
  required String id,
  required String name,
  required int dayWeek,
  required int sectionStart,
  required int sectionEnd,
  int weekMask = 0xFFFFF,
  String location = '教学楼A101',
}) {
  return Course(
    id: id,
    name: name,
    teacher: '张三',
    location: location,
    colorValue: 4294198070,
    dayWeek: dayWeek,
    sectionStart: sectionStart,
    sectionEnd: sectionEnd,
    weekMask: weekMask,
    note: '',
  );
}

void main() {
  test('学期未配置 → 空列表', () {
    final TimetableData data = TimetableData.empty();
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups, isEmpty);
  });

  test('本周停课（cancelled override）的课不出现在当天分组里', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '高等数学',
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
        ),
      ],
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

    // saturday（10-17）是第 6 周周六 → 当天分组应为空
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups.first.items, isEmpty);
  });

  test('周六有课：分组数、header 文案、课程内容全部正确', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '高等数学',
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
          location: '实验楼C101',
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups.length, 7);
    expect(groups.first.dateKey, '2026-10-17');
    expect(groups.first.header, '10月17日 周六 · 第6周');
    expect(groups.first.items.length, 1);
    final TodayItem item = groups.first.items.single;
    expect(item.title, '高等数学');
    expect(item.location, '实验楼C101');
    expect(item.timeText, '08:30-10:05');
    expect(item.color, 4294198070);
  });

  test('当天没课 → 该组 items 为空但 header 仍有日期', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '计算机网络',
          dayWeek: 1,
          sectionStart: 3,
          sectionEnd: 4,
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups.first.items, isEmpty);
    expect(groups.first.header, '10月17日 周六 · 第6周');
    // 10-19（下周一）那组有课；第 6 周是 10-12~10-18，所以 10-19 已进入第 7 周
    expect(groups[2].header, '10月19日 周一 · 第7周');
    expect(groups[2].items.single.title, '计算机网络');
  });

  test('跨周：7 天窗口跨进第 7 周，周次与课程都对', () {
    // 第 6 周周六起：周日还在第 6 周，下周一进入第 7 周
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_002',
          name: '大学物理',
          dayWeek: 1,
          sectionStart: 3,
          sectionEnd: 4,
          weekMask: 1 << 6, // 仅第 7 周
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups[2].header, '10月19日 周一 · 第7周');
    expect(groups[2].items.single.title, '大学物理');
    // 第 6 周的周六（第 0 组）没有这门课
    expect(groups.first.items, isEmpty);
  });

  test('override 生效：调课后时间与地点变化', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '计算机网络',
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
        ),
      ],
      overrides: <CourseOverride>[
        CourseOverride(
          courseId: 'c_001',
          week: 6,
          dayWeek: 6,
          sectionStart: 5,
          sectionEnd: 6,
          location: '实验楼B203',
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    final TodayItem item = groups.first.items.single;
    expect(item.timeText, '14:40-16:15');
    expect(item.location, '实验楼B203');
  });

  test('乱序课程 → items 按节次升序', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_003',
          name: 'C',
          dayWeek: 6,
          sectionStart: 5,
          sectionEnd: 6,
        ),
        _course(
          id: 'c_001',
          name: 'A',
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
        ),
        _course(
          id: 'c_002',
          name: 'B',
          dayWeek: 6,
          sectionStart: 3,
          sectionEnd: 4,
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(
      groups.first.items.map((TodayItem item) => item.title).toList(),
      <String>['A', 'B', 'C'],
    );
  });

  test('节次越界（脏数据）→ timeText 回退为「第N-M节」不抛异常', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '越界课',
          dayWeek: 6,
          sectionStart: 99,
          sectionEnd: 100,
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    expect(groups.first.items.single.timeText, '第99-100节');
  });

  test('encodeList 输出的 JSON 结构与 Kotlin 契约一致', () {
    final TimetableData data = _data(
      courses: <Course>[
        _course(
          id: 'c_001',
          name: '高等数学',
          dayWeek: 6,
          sectionStart: 1,
          sectionEnd: 2,
        ),
      ],
    );
    final List<TodayGroup> groups = todayGroups(data, saturday);
    final dynamic decoded = jsonDecode(TodayGroup.encodeList(groups));
    expect(decoded, isA<List<dynamic>>());
    final Map<String, dynamic> first =
        (decoded as List<dynamic>).first as Map<String, dynamic>;
    expect(first['date'], '2026-10-17');
    expect(first['header'], '10月17日 周六 · 第6周');
    final Map<String, dynamic> item =
        (first['items'] as List<dynamic>).single as Map<String, dynamic>;
    expect(item['timeText'], '08:30-10:05');
    expect(item['title'], '高等数学');
    expect(item['color'], '4294198070');
  });

  test('空列表 encodeList 输出 "[]"（覆盖旧数据，跨天不残留）', () {
    expect(TodayGroup.encodeList(const <TodayGroup>[]), '[]');
  });
}
