import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/models/timetable_data.dart';

void main() {
  group('TimetableData JSON 契约', () {
    final Map<String, dynamic> json = <String, dynamic>{
      'schema': 1,
      'meta': <String, dynamic>{
        'school': '广东科技学院',
        'semesterName': '2026-2027 第一学期',
        'week1Monday': '2026-09-07',
        'totalWeeks': 20,
      },
      'periods': <dynamic>[
        <String, dynamic>{'index': 1, 'start': '08:30', 'end': '09:15'},
      ],
      'courses': <dynamic>[
        <String, dynamic>{
          'id': 'c_001',
          'name': '计算机网络',
          'teacher': '张三',
          'location': '教学楼A101',
          'colorValue': 4294198070,
          'dayWeek': 1,
          'sectionStart': 3,
          'sectionEnd': 4,
          'weekMask': 65535,
          'note': '',
        },
      ],
      'overrides': <dynamic>[],
    };

    test('fromJson 正确解析各字段', () {
      final TimetableData data = TimetableData.fromJson(json);
      expect(data.schema, 1);
      expect(data.meta.week1Monday, DateTime(2026, 9, 7));
      expect(data.courses.single.name, '计算机网络');
      expect(data.courses.single.weekMask, 65535);
      expect(data.courses.single.sectionStart, 3);
      expect(data.courses.single.sectionEnd, 4);
    });

    test('toJson 保持契约字段名与日期格式', () {
      final Map<String, dynamic> out = TimetableData.fromJson(json).toJson();
      expect(out['meta']['week1Monday'], '2026-09-07');
      expect(out['courses'][0]['sectionEnd'], 4);
      expect(out['courses'][0]['colorValue'], 4294198070);
    });

    test('缺省 colorValue 时按课程名兜底取色', () {
      final Course course = Course.fromJson(<String, dynamic>{'name': '体育'});
      expect(course.colorValue, isNot(0));
    });

    test('empty 使用广科默认 10 节作息', () {
      final TimetableData data = TimetableData.empty();
      expect(data.periods.length, 10);
      expect(data.periods.first.start, '08:30');
      expect(data.periods.last.end, '21:05');
    });
  });
}
