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

    test('App 备份但 courses 为空 → 报「备份文件里没有课程」', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        'schema': 1,
        'meta': <String, dynamic>{},
        'periods': <dynamic>[],
        'courses': <dynamic>[],
      });

      expect(result.courses, isEmpty);
      expect(result.error, contains('没有课程'));
      expect(result.isSuccessful, isFalse);
    });

    test('App 备份结构坏（schema 类型错）→ 备份报错而不是崩溃', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        'schema': 'one',
        'courses': <dynamic>[],
      });

      expect(result.isSuccessful, isFalse);
      expect(result.error, contains('备份文件无法解析'));
    });
  });

  group('App 备份完整恢复（J11）', () {
    test('含 courses 键的 App 备份 → 学期 / 作息 / 调整全带回，不再报错', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
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
        'overrides': <dynamic>[
          <String, dynamic>{
            'courseId': 'c_001',
            'week': 8,
            'dayWeek': 3,
            'sectionStart': 5,
            'sectionEnd': 6,
            'location': '实验楼B203',
          },
        ],
      });

      expect(result.error, isNull);
      expect(result.courses.single.id, 'c_001');
      expect(result.courses.single.name, '计算机网络');
      expect(result.courses.single.sectionStart, 3);
      expect(result.courses.single.sectionEnd, 4);
      expect(result.meta, isNotNull);
      expect(result.meta!.semesterName, '2026-2027 第一学期');
      expect(result.meta!.week1Monday, DateTime(2026, 9, 7));
      expect(result.meta!.totalWeeks, 20);
      expect(result.periods, isNotNull);
      expect(result.periods!.single.start, '08:30');
      expect(result.overrides, isNotNull);
      expect(result.overrides!.single.courseId, 'c_001');
      expect(result.overrides!.single.location, '实验楼B203');
      expect(result.skippedCount, 0);
    });

    test('App 备份的 meta 未配置 → meta 为 null，课程照常恢复', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        'schema': 1,
        'meta': <String, dynamic>{
          'school': '广东科技学院',
          'semesterName': '',
          'week1Monday': '',
          'totalWeeks': 20,
        },
        'periods': <dynamic>[],
        'courses': <dynamic>[
          <String, dynamic>{
            'id': 'c_001',
            'name': '计算机网络',
            'teacher': '',
            'location': '',
            'colorValue': 0,
            'dayWeek': 1,
            'sectionStart': 3,
            'sectionEnd': 3,
            'weekMask': 1,
            'note': '',
          },
        ],
        'overrides': <dynamic>[],
      });

      expect(result.error, isNull);
      expect(result.courses.single.name, '计算机网络');
      expect(result.meta, isNull);
      // periods 为空数组时 fromJson 回退默认作息，仍然带回
      expect(result.periods, isNotNull);
      expect(result.overrides, isNotNull);
      expect(result.overrides, isEmpty);
    });
  });

  group('教务 JSON 顶层 meta / periods（J11）', () {
    Map<String, dynamic> weekRoot() => <String, dynamic>{
      '1': <Map<String, dynamic>>[entry()],
    };

    Map<String, dynamic> validMeta() => <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '2026-2027年第1学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    };

    List<dynamic> validPeriods() => <dynamic>[
      <String, dynamic>{'index': 1, 'start': '08:30', 'end': '09:15'},
      <String, dynamic>{'index': 2, 'start': '09:20', 'end': '10:05'},
    ];

    test('带合法 meta + periods → 一并带回，不再被误判为 App 格式', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': validMeta(),
        'periods': validPeriods(),
      });

      expect(result.isSuccessful, isTrue);
      expect(result.error, isNull);
      expect(result.courses.length, 1);
      expect(result.meta, isNotNull);
      expect(result.meta!.week1Monday, DateTime(2026, 9, 7));
      expect(result.meta!.totalWeeks, 20);
      expect(result.meta!.semesterName, '2026-2027年第1学期');
      expect(result.periods, isNotNull);
      expect(result.periods!.length, 2);
      // 教务 JSON 没有 overrides
      expect(result.overrides, isNull);
    });

    test('meta 非法（week1Monday 缺失）→ 忽略，课程照常导入', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': <String, dynamic>{'totalWeeks': 20},
      });

      expect(result.courses.length, 1);
      expect(result.meta, isNull);
    });

    test('meta 非法（totalWeeks 越界 99）→ 忽略', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': <String, dynamic>{...validMeta(), 'totalWeeks': 99},
      });

      expect(result.courses.length, 1);
      expect(result.meta, isNull);
    });

    test('meta totalWeeks 边界 32 → 合法', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': <String, dynamic>{...validMeta(), 'totalWeeks': 32},
      });

      expect(result.meta, isNotNull);
      expect(result.meta!.totalWeeks, 32);
    });

    test('meta totalWeeks 是字符串（类型错）→ 忽略而不崩溃', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': <String, dynamic>{...validMeta(), 'totalWeeks': '20'},
      });

      expect(result.courses.length, 1);
      expect(result.meta, isNull);
    });

    test('meta 不是对象 → 忽略', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'meta': '广科',
      });

      expect(result.courses.length, 1);
      expect(result.meta, isNull);
    });

    test('periods 非法（3 节中第 2 节 start >= end）→ 整体忽略', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'periods': <dynamic>[
          <String, dynamic>{'index': 1, 'start': '08:30', 'end': '09:15'},
          <String, dynamic>{'index': 2, 'start': '10:00', 'end': '10:00'},
          <String, dynamic>{'index': 3, 'start': '10:25', 'end': '11:10'},
        ],
      });

      expect(result.courses.length, 1);
      expect(result.periods, isNull);
    });

    test('periods 非法（index 断裂）→ 整体忽略', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'periods': <dynamic>[
          <String, dynamic>{'index': 1, 'start': '08:30', 'end': '09:15'},
          <String, dynamic>{'index': 3, 'start': '09:20', 'end': '10:05'},
        ],
      });

      expect(result.periods, isNull);
    });

    test('periods 不是数组 → 忽略', () {
      final ImportResult result = parseImportedTimetable(<String, dynamic>{
        ...weekRoot(),
        'periods': '见作息表',
      });

      expect(result.periods, isNull);
    });

    test('老 JSON（不带 meta / periods）→ 均为 null，行为与旧版一致', () {
      final ImportResult result = parseImportedTimetable(weekRoot());

      expect(result.courses.length, 1);
      expect(result.meta, isNull);
      expect(result.periods, isNull);
      expect(result.overrides, isNull);
    });
  });
}
