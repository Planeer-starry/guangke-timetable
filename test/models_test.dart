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

  group('semesterConfigured 与哨兵值（回归：存盘往返不能误判）', () {
    // 曾经的 bug：unsetWeek1Monday 是 DateTime.utc(1,1,1)，而 toJson 存的是
    // 不带时区的 "0001-01-01"，DateTime.parse 按本地时区解析出 DateTime(1,1,1)，
    // 两者相差一个时区偏移、并不相等 → 存盘再读之后「未配置」被误判成「已配置」，
    // 于是用公元 1 年算周次（截断成第 20 周），首页显示空课表且不提示设置学期。
    test('内存中的 empty → 未配置', () {
      expect(TimetableData.empty().semesterConfigured, isFalse);
    });

    test('empty 存盘再读回来 → 仍然是未配置', () {
      final TimetableData restored = TimetableData.fromJson(
        TimetableData.empty().toJson(),
      );
      expect(restored.semesterConfigured, isFalse);
      expect(restored.meta.week1Monday, TimetableData.unsetWeek1Monday);
    });

    test('JSON 里写 "0001-01-01" → 归一成哨兵值、未配置', () {
      final Map<String, dynamic> raw = TimetableData.empty()
          .toJson()
          .cast<String, dynamic>();
      (raw['meta'] as Map<String, dynamic>)['week1Monday'] = '0001-01-01';
      final TimetableData restored = TimetableData.fromJson(raw);
      expect(restored.semesterConfigured, isFalse);
      expect(restored.meta.week1Monday, TimetableData.unsetWeek1Monday);
    });

    test('正常学期日期 → 已配置，且日期不丢', () {
      final TimetableData restored = TimetableData.fromJson(<String, dynamic>{
        'schema': 1,
        'meta': <String, dynamic>{
          'school': '广东科技学院',
          'semesterName': '2026-2027 第一学期',
          'week1Monday': '2026-09-07',
          'totalWeeks': 20,
        },
      });
      expect(restored.semesterConfigured, isTrue);
      expect(restored.meta.week1Monday.year, 2026);
      expect(restored.meta.week1Monday.month, 9);
      expect(restored.meta.week1Monday.day, 7);
    });
  });
}
