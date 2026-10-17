import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/utils/timetable_importer.dart';
import 'package:timetable/utils/week_mask.dart';

Map<String, dynamic> entry({
  String name = '计算机网络',
  String teacher = '张三',
  String location = '教学楼A101',
  Object? section,
  Object? dayWeek = 1,
  Object? week,
}) {
  return <String, dynamic>{
    'courseName': name,
    'teacher': teacher,
    'classroomName': location,
    'whichSection': section ?? 3,
    'dayWeek': dayWeek,
    'week': ?week,
  };
}

void main() {
  group('基础聚合', () {
    test('单周单次课 → 1 门课，weekMask 只有 1 位', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry()],
      });

      expect(result.courses.length, 1);
      expect(result.courses.single.name, '计算机网络');
      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 3);
      expect(weeksFromWeekMask(result.courses.single.weekMask), <int>[1]);
      expect(result.skippedCount, 0);
    });

    test('同一门课出现在 1~16 周 → 1 门课，weekMask = 0xFFFF', () {
      final Map<String, dynamic> root = <String, dynamic>{};
      for (int week = 1; week <= 16; week++) {
        root['$week'] = <Map<String, dynamic>>[entry(section: 3)];
      }

      final ImportResult result = parseImportedTimetable(root);

      expect(result.courses.length, 1);
      expect(result.courses.single.weekMask, 0xFFFF);
    });

    test('连堂 3-4 节（两条记录）→ 1 门课，sectionStart=3, sectionEnd=4', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: 3), entry(section: 4)],
      });

      expect(result.courses.length, 1);
      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 4);
    });

    test('不连续节次（3 和 5）绝对不能被合并', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: 3), entry(section: 5)],
      });

      expect(result.courses.length, 2);
      final Set<String> ranges = result.courses
          .map((Course c) => '${c.sectionStart}-${c.sectionEnd}')
          .toSet();
      expect(ranges, <String>{'3-3', '5-5'});
    });

    test('同周同节重复条目去重', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: 3), entry(section: 3)],
      });

      expect(result.courses.length, 1);
      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 3);
    });
  });

  group('section 节次集合解析', () {
    test('jcs = "3-4" → 连堂 3~4', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: '3-4')],
      });

      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 4);
    });

    test('section = [3,4] 数组 → 连堂 3~4', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[
          entry(section: <int>[3, 4]),
        ],
      });

      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 4);
    });

    test('section = "3" 字符串 → 单节', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: '3')],
      });

      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 3);
    });

    test('畸形区间 sectionStart > sectionEnd 按交换归一', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(section: '4-3')],
      });

      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 4);
    });

    test('越界节次（0、11）被过滤', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[
          entry(section: <int>[0, 11, 3]),
        ],
      });

      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 3);
    });
  });

  group('字段别名', () {
    test('kcmc / xm / jxdd / jcs / xqj 能正确解析', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '2': <Map<String, dynamic>>[
          <String, dynamic>{
            'kcmc': '高等数学',
            'xm': '李四',
            'jxdd': '教学楼B202',
            'jcs': '5-6',
            'xqj': 2,
          },
        ],
      });

      expect(result.courses.length, 1);
      expect(result.courses.single.name, '高等数学');
      expect(result.courses.single.teacher, '李四');
      expect(result.courses.single.location, '教学楼B202');
      expect(result.courses.single.dayWeek, 2);
      expect(result.courses.single.sectionStart, 5);
      expect(result.courses.single.sectionEnd, 6);
    });
  });

  group('周次与校验', () {
    test('周次以字典的键为准（条目 week 冲突时以键为准）', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '3': <Map<String, dynamic>>[entry(week: 9)],
      });

      expect(weeksFromWeekMask(result.courses.single.weekMask), <int>[3]);
    });

    test('dayWeek 越界（8）的条目被跳过并计数', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[entry(dayWeek: 8), entry()],
      });

      expect(result.courses.length, 1);
      expect(result.skippedCount, 1);
    });

    test('缺字段的条目被跳过并计数，不崩', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[
          <String, dynamic>{'kcmc': '缺地点'},
        ],
      });

      expect(result.courses, isEmpty);
      expect(result.skippedCount, 1);
    });
  });

  group('错误识别', () {
    test('空对象 → 报「未识别到任何课程」', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{});

      expect(result.courses, isEmpty);
      expect(result.error, isNotNull);
      expect(result.isSuccessful, isFalse);
    });

    test('空周 → 报「未识别到任何课程」', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <Map<String, dynamic>>[],
      });

      expect(result.courses, isEmpty);
      expect(result.error, isNotNull);
    });

    test('App 自身导出格式 → 给出明确报错', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        'schema': 1,
        'meta': <String, dynamic>{},
        'periods': <dynamic>[],
        'courses': <dynamic>[],
      });

      expect(result.courses, isEmpty);
      expect(result.error, contains('App 导出'));
      expect(result.isSuccessful, isFalse);
    });
  });
}
