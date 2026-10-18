import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/course_editor.dart';

Course courseOf(
  String id, {
  String name = '计算机网络',
  int dayWeek = 1,
  int sectionStart = 3,
  int sectionEnd = 4,
  int weekMask = 0xFFFF,
}) {
  return Course(
    id: id,
    name: name,
    teacher: '张三',
    location: '教学楼A101',
    colorValue: 4294198070,
    dayWeek: dayWeek,
    sectionStart: sectionStart,
    sectionEnd: sectionEnd,
    weekMask: weekMask,
  );
}

TimetableData dataOf({
  List<Course> courses = const <Course>[],
  List<CourseOverride> overrides = const <CourseOverride>[],
}) {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': courses.map((Course c) => c.toJson()).toList(),
    'overrides': overrides.map((CourseOverride o) => o.toJson()).toList(),
  });
}

void main() {
  group('upsertCourse', () {
    test('id 不存在 → 追加，列表 +1', () {
      final TimetableData data = dataOf(courses: <Course>[courseOf('c_001')]);

      final TimetableData updated = CourseEditor.upsertCourse(
        data,
        courseOf('u_001', name: '高等数学'),
      );

      expect(updated.courses.length, 2);
      expect(updated.courses.last.id, 'u_001');
      expect(updated.courses.last.name, '高等数学');
      // 原数据不被改动
      expect(data.courses.length, 1);
    });

    test('id 已存在 → 原位替换，列表长度不变，内容更新', () {
      final TimetableData data = dataOf(
        courses: <Course>[
          courseOf('c_001'),
          courseOf('c_002', name: '大学英语'),
        ],
      );

      final TimetableData updated = CourseEditor.upsertCourse(
        data,
        courseOf('c_002', name: '大学英语（口语）', dayWeek: 5),
      );

      expect(updated.courses.length, 2);
      // 原位替换：仍在第二个
      expect(updated.courses[1].name, '大学英语（口语）');
      expect(updated.courses[1].dayWeek, 5);
      expect(updated.courses[0].id, 'c_001');
    });
  });

  group('deleteCourse', () {
    test('删课后该 courseId 的 overrides 一并删除', () {
      final TimetableData data = dataOf(
        courses: <Course>[courseOf('c_001'), courseOf('c_002')],
        overrides: <CourseOverride>[
          CourseOverride(
            courseId: 'c_001',
            week: 8,
            dayWeek: 3,
            sectionStart: 5,
            sectionEnd: 6,
            location: '实验楼B203',
          ),
          CourseOverride(
            courseId: 'c_002',
            week: 9,
            dayWeek: 2,
            sectionStart: 1,
            sectionEnd: 2,
            location: '教学楼C305',
          ),
        ],
      );

      final TimetableData updated = CourseEditor.deleteCourse(data, 'c_001');

      expect(updated.courses.length, 1);
      expect(updated.courses.single.id, 'c_002');
      // c_001 的 override 已删，c_002 的保留
      expect(updated.overrides.length, 1);
      expect(updated.overrides.single.courseId, 'c_002');
    });

    test('删除不存在的 id → 原样返回（不抛异常）', () {
      final TimetableData data = dataOf(courses: <Course>[courseOf('c_001')]);

      final TimetableData updated = CourseEditor.deleteCourse(data, 'nope');

      expect(updated.courses.length, 1);
    });
  });

  group('newCourseId', () {
    test('空列表 → u_001', () {
      expect(CourseEditor.newCourseId(dataOf()), 'u_001');
    });

    test('只有导入前缀 c_/jw_ → 不影响编号，仍是 u_001', () {
      final TimetableData data = dataOf(
        courses: <Course>[courseOf('c_001'), courseOf('jw_002')],
      );

      expect(CourseEditor.newCourseId(data), 'u_001');
    });

    test('已有 u_001/u_003 → u_004（取最大值 +1，非数量 +1）', () {
      final TimetableData data = dataOf(
        courses: <Course>[courseOf('u_001'), courseOf('u_003')],
      );

      expect(CourseEditor.newCourseId(data), 'u_004');
    });
  });

  group('setOverride', () {
    test('同 (courseId, week) 已存在 → 原位替换，不重复', () {
      final CourseOverride first = CourseOverride(
        courseId: 'c_001',
        week: 8,
        dayWeek: 3,
        sectionStart: 5,
        sectionEnd: 6,
        location: '实验楼B203',
      );
      final CourseOverride second = CourseOverride(
        courseId: 'c_001',
        week: 8,
        dayWeek: 5,
        sectionStart: 1,
        sectionEnd: 2,
        location: '教学楼C305',
      );
      final TimetableData data = dataOf(
        courses: <Course>[courseOf('c_001')],
        overrides: <CourseOverride>[first],
      );

      final TimetableData updated = CourseEditor.setOverride(data, second);

      expect(updated.overrides.length, 1);
      expect(updated.overrides.single.dayWeek, 5);
      expect(updated.overrides.single.sectionStart, 1);
      expect(updated.overrides.single.location, '教学楼C305');
      // 原数据不被改动
      expect(data.overrides.length, 1);
      expect(data.overrides.single.dayWeek, 3);
    });

    test('同 courseId 不同周 / 不同 courseId 同周 → 各自独立追加', () {
      final TimetableData data = dataOf(
        courses: <Course>[courseOf('c_001'), courseOf('c_002')],
        overrides: <CourseOverride>[
          CourseOverride(
            courseId: 'c_001',
            week: 8,
            dayWeek: 3,
            sectionStart: 5,
            sectionEnd: 6,
            location: '实验楼B203',
          ),
        ],
      );

      final TimetableData updated = CourseEditor.setOverride(
        data,
        CourseOverride(
          courseId: 'c_001',
          week: 9,
          dayWeek: 2,
          sectionStart: 1,
          sectionEnd: 2,
          location: '教学楼D402',
        ),
      );
      final TimetableData updated2 = CourseEditor.setOverride(
        updated,
        CourseOverride(
          courseId: 'c_002',
          week: 8,
          dayWeek: 4,
          sectionStart: 7,
          sectionEnd: 8,
          location: '实验楼E101',
        ),
      );

      // 同 courseId 不同周：追加
      expect(updated.overrides.length, 2);
      // 不同 courseId 同周：再追加
      expect(updated2.overrides.length, 3);
    });
  });

  group('copyWith 各字段独立生效', () {
    test('Course.copyWith 只改传入字段，id 永远不变', () {
      final Course original = courseOf('c_001');

      final Course renamed = original.copyWith(name: '数据结构');
      expect(renamed.name, '数据结构');
      expect(renamed.dayWeek, original.dayWeek);
      expect(renamed.sectionStart, original.sectionStart);
      expect(renamed.weekMask, original.weekMask);
      expect(renamed.id, 'c_001');

      final Course moved = original.copyWith(dayWeek: 5, sectionStart: 1);
      expect(moved.dayWeek, 5);
      expect(moved.sectionStart, 1);
      // 未传的字段保持
      expect(moved.sectionEnd, original.sectionEnd);
      expect(moved.name, original.name);
      expect(moved.id, 'c_001');
    });

    test('TimetableData.copyWith 只替换传入的列表', () {
      final TimetableData data = dataOf(courses: <Course>[courseOf('c_001')]);

      final TimetableData updated = data.copyWith(
        overrides: <CourseOverride>[
          CourseOverride(
            courseId: 'c_001',
            week: 8,
            dayWeek: 3,
            sectionStart: 5,
            sectionEnd: 6,
            location: '实验楼B203',
          ),
        ],
      );

      expect(updated.overrides.length, 1);
      // courses 未传 → 保持
      expect(updated.courses.length, 1);
      expect(updated.meta, data.meta);
      expect(updated.schema, data.schema);
    });
  });
}
