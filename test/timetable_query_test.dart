import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/timetable_query.dart';

TimetableData buildData({
  required List<Map<String, dynamic>> courses,
  List<Map<String, dynamic>> overrides = const <Map<String, dynamic>>[],
}) {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': courses,
    'overrides': overrides,
  });
}

Map<String, dynamic> courseJson({
  String id = 'c_001',
  String name = '计算机网络',
  int dayWeek = 1,
  int sectionStart = 3,
  int sectionEnd = 4,
  int weekMask = 0xFFFF,
  String location = '教学楼A101',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'teacher': '张三',
    'location': location,
    'colorValue': 4294198070,
    'dayWeek': dayWeek,
    'sectionStart': sectionStart,
    'sectionEnd': sectionEnd,
    'weekMask': weekMask,
    'note': '',
  };
}

Map<String, dynamic> overrideJson({required int week}) {
  return <String, dynamic>{
    'courseId': 'c_001',
    'week': week,
    'dayWeek': 3,
    'sectionStart': 5,
    'sectionEnd': 6,
    'location': '实验楼B203',
  };
}

void main() {
  group('coursesForWeek', () {
    test('无 override 时与 course 字段一致', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[courseJson()],
      );

      final List<CourseOccurrence> result = coursesForWeek(data, 1);

      expect(result.length, 1);
      expect(result.single.course.name, '计算机网络');
      expect(result.single.dayWeek, 1);
      expect(result.single.sectionStart, 3);
      expect(result.single.sectionEnd, 4);
      expect(result.single.location, '教学楼A101');
    });

    test('有 override 时时段与地点被替换', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[courseJson()],
        overrides: <Map<String, dynamic>>[overrideJson(week: 8)],
      );

      final List<CourseOccurrence> result = coursesForWeek(data, 8);

      expect(result.single.dayWeek, 3);
      expect(result.single.sectionStart, 5);
      expect(result.single.sectionEnd, 6);
      expect(result.single.location, '实验楼B203');
      expect(result.single.course.name, '计算机网络');
    });

    test('override 只影响匹配的那一周', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[courseJson()],
        overrides: <Map<String, dynamic>>[overrideJson(week: 8)],
      );

      final List<CourseOccurrence> normalWeek = coursesForWeek(data, 1);

      expect(normalWeek.single.dayWeek, 1);
      expect(normalWeek.single.sectionStart, 3);
      expect(normalWeek.single.location, '教学楼A101');
    });

    test('按 weekMask 筛选：该周无课的课不出现在结果里', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          courseJson(weekMask: 0x1),
          courseJson(id: 'c_002', name: '高等数学', weekMask: 0x2),
        ],
      );

      expect(coursesForWeek(data, 1).single.course.id, 'c_001');
      expect(coursesForWeek(data, 2).single.course.id, 'c_002');
      expect(coursesForWeek(data, 3), isEmpty);
    });

    test('空课程列表 → 空结果', () {
      final TimetableData data = buildData(courses: <Map<String, dynamic>>[]);
      expect(coursesForWeek(data, 1), isEmpty);
    });
  });
}
