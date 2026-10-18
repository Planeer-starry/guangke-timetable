import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/course_override.dart';

CourseOverride overrideOf({bool cancelled = false}) {
  return CourseOverride(
    courseId: 'c_001',
    week: 8,
    dayWeek: 3,
    sectionStart: 5,
    sectionEnd: 6,
    location: '实验楼B203',
    cancelled: cancelled,
  );
}

void main() {
  group('CourseOverride cancelled JSON 序列化', () {
    test('cancelled: true 往返一致', () {
      final CourseOverride original = overrideOf(cancelled: true);

      final CourseOverride round = CourseOverride.fromJson(original.toJson());

      expect(round.cancelled, true);
      expect(round.courseId, 'c_001');
      expect(round.week, 8);
      expect(round.location, '实验楼B203');
    });

    test('cancelled: false 往返一致', () {
      final CourseOverride round = CourseOverride.fromJson(
        overrideOf().toJson(),
      );

      expect(round.cancelled, false);
    });

    test('旧 JSON 无 cancelled 字段 → 解析为 false，不抛异常', () {
      final CourseOverride round = CourseOverride.fromJson(<String, dynamic>{
        'courseId': 'c_001',
        'week': 8,
        'dayWeek': 3,
        'sectionStart': 5,
        'sectionEnd': 6,
        'location': '实验楼B203',
      });

      expect(round.cancelled, false);
      expect(round.location, '实验楼B203');
      expect(round.sectionEnd, 6);
    });
  });
}
