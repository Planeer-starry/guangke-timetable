import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/utils/timetable_importer.dart';

/// 校验 `tools/gdust_crawl/` 爬虫产出的 JSON 能被 App 的导入器正确接受。
///
/// 爬虫无法在真实教务系统上验证（需要账号），但它和 App 之间的**契约**
/// 可以在这里锁死：只要这个测试绿，爬虫生成的文件就能导入。
void main() {
  group('爬虫输出格式 → 导入器契约', () {
    test('单周单课：字段全对', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <dynamic>[
          <String, dynamic>{
            'courseName': '高等数学BⅠ',
            'teacher': '谌凤霞',
            'classroomName': '松6-502',
            'dayWeek': 2,
            'whichSection': '7-8',
          },
        ],
      });

      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.skippedCount, 0);
      final course = result.courses.single;
      expect(course.name, '高等数学BⅠ');
      expect(course.teacher, '谌凤霞');
      expect(course.location, '松6-502');
      expect(course.dayWeek, 2);
      // "7-8" 被拆成两个节次后重新聚合成 7~8
      expect(course.sectionStart, 7);
      expect(course.sectionEnd, 8);
      expect(course.weekMask, 1 << 0); // 只有第 1 周
    });

    test('跨周重复出现 → 聚合成一门课，周次按位掩码累积', () {
      // 爬虫对一门 3~5 周的课，会在 "3"、"4"、"5" 三个键里各留一条
      Map<String, dynamic> weekEntry() => <String, dynamic>{
        'courseName': '大学英语Ⅰ',
        'teacher': '刘璐璐',
        'classroomName': '松L4-502',
        'dayWeek': 3,
        'whichSection': '1-2',
      };

      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '3': <dynamic>[weekEntry()],
        '4': <dynamic>[weekEntry()],
        '5': <dynamic>[weekEntry()],
      });

      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      final course = result.courses.single;
      expect(course.name, '大学英语Ⅰ');
      // 第 3/4/5 周 → bit 2,3,4
      expect(course.weekMask, (1 << 2) | (1 << 3) | (1 << 4));
    });

    test('空周数组不影响结果（爬虫对没课的周输出 []）', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <dynamic>[],
        '2': <dynamic>[
          <String, dynamic>{
            'courseName': '大学体育Ⅰ',
            'teacher': '李大勇',
            'classroomName': '田径场',
            'dayWeek': 4,
            'whichSection': '3-4',
          },
        ],
        '3': <dynamic>[],
      });

      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.weekMask, 1 << 1); // 第 2 周
    });

    test('非正方字段名（通用别名）同样接受', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <dynamic>[
          <String, dynamic>{
            'courseName': '线性代数',
            'teacherName': '王五',
            'classroom': '教1-201',
            'dayWeek': 1,
            'section': '5-6',
          },
        ],
      });

      expect(result.error, isNull);
      expect(result.courses.single.teacher, '王五');
      expect(result.courses.single.location, '教1-201');
    });

    test('脏数据：dayWeek 越界 → 计入 skippedCount，不抛异常', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <dynamic>[
          <String, dynamic>{
            'courseName': '正常的课',
            'dayWeek': 2,
            'whichSection': '1-2',
          },
          <String, dynamic>{
            'courseName': '星期越界的课',
            'dayWeek': 9,
            'whichSection': '1-2',
          },
          <String, dynamic>{
            'courseName': '缺星期',
            'whichSection': '1-2',
          },
        ],
      });

      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.name, '正常的课');
      expect(result.skippedCount, 2);
    });

    test('全部为空 → 返回错误而不是空课程列表', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        '1': <dynamic>[],
        '2': <dynamic>[],
      });

      expect(result.error, isNotNull);
      expect(result.courses, isEmpty);
    });
  });
}
