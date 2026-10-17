import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/week_mask.dart';

void main() {
  group('A. 周次文本解析 parseWeeksText', () {
    test('连续区间 "11-14周"', () {
      expect(parseWeeksText('11-14周'), <int>{11, 12, 13, 14});
    });

    test('双周 "8-18周(双)"', () {
      expect(parseWeeksText('8-18周(双)'), <int>{8, 10, 12, 14, 16, 18});
    });

    test('单周 "7-17周(单)"', () {
      expect(parseWeeksText('7-17周(单)'), <int>{7, 9, 11, 13, 15, 17});
    });

    test('区间 + 单周 "7-17周,19周"', () {
      expect(parseWeeksText('7-17周,19周'), <int>{
        7,
        8,
        9,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        19,
      });
    });

    test('单个周次 "15周"', () {
      expect(parseWeeksText('15周'), <int>{15});
    });

    test('短区间 "3-4周"', () {
      expect(parseWeeksText('3-4周'), <int>{3, 4});
    });

    test('全角括号 "8-18周（双）"', () {
      expect(parseWeeksText('8-18周（双）'), <int>{8, 10, 12, 14, 16, 18});
    });

    test('整学期 "1-20周"', () {
      expect(parseWeeksText('1-20周'), {for (int i = 1; i <= 20; i++) i});
    });

    test('空字符串 / 乱码 → 空集合不抛', () {
      expect(parseWeeksText(''), isEmpty);
      expect(parseWeeksText('   '), isEmpty);
      expect(parseWeeksText('第?周'), isEmpty);
    });
  });

  group('B. 单元格解析 parseCellText', () {
    test('一格单课：字段全部正确', () {
      final List<JwxtCellEntry> entries = parseCellText(
        '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/'
        '(2026-2027-1)-10013C0002-20/26软件3班/80/ /',
      );
      expect(entries, hasLength(1));
      final JwxtCellEntry e = entries.single;
      expect(e.name, '计算机网络');
      expect(e.sectionStart, 3);
      expect(e.sectionEnd, 4);
      expect(e.weeks, {for (int i = 1; i <= 16; i++) i});
      expect(e.location, '松3-302');
      expect(e.teacher, '张三');
    });

    test('一格多课（真实样本：军事理论 + 大学生创新教育Ⅰ）', () {
      final List<JwxtCellEntry> entries = parseCellText(
        '军事理论/(1-2节)11-14周/松山湖 松6-604/华康/'
        '(2026-2027-1)-10013C0002-20/26卓越软件工程师3班;26卓越软件工程师4班/90/ /'
        '\n大学生创新教育Ⅰ/(1-2节)11-14周/松山湖 松6-604/李四/'
        '(2026-2027-1)-10013C0002-30/26卓越软件工程师3班/90/ /',
      );
      expect(entries, hasLength(2));
      expect(entries[0].name, '军事理论');
      expect(entries[0].teacher, '华康');
      expect(entries[1].name, '大学生创新教育Ⅰ');
      expect(entries[1].teacher, '李四');
    });

    test('前导换行被 trim', () {
      final List<JwxtCellEntry> entries = parseCellText(
        '\n大学生创新教育Ⅰ/(1-2节)11-14周/松山湖 松6-604/李四/(x)/y/90/ /',
      );
      expect(entries.single.name, '大学生创新教育Ⅰ');
    });

    test('地点取最后一个空格后的部分', () {
      final List<JwxtCellEntry> entries = parseCellText(
        '军事理论/(1-2节)11-14周/松山湖 松6-604/华康/(x)/y/90/ /',
      );
      expect(entries.single.location, '松6-604');
    });

    test('空格分隔的裸地点不会被截坏', () {
      const String raw = '松山湖 松6-604';
      final List<String> parts = raw.trim().split(' ');
      expect(parts.last, '松6-604');
    });
  });

  group('C. 元信息提取', () {
    test('真实注释行：week1Monday=2026-08-31, totalWeeks=20', () {
      final JwxtImportResult result = parseJwxtWorkbook(
        _workbookWithNote('注--：本学期2026-08-31正式上课至2027-01-17结束，共20周.'),
      );
      expect(result.week1Monday, DateTime(2026, 8, 31));
      expect(result.totalWeeks, 20);
    });

    test('注释行缺失 → null 不抛', () {
      final JwxtImportResult result = parseJwxtWorkbook(
        _workbookWithNote(null),
      );
      expect(result.week1Monday, isNull);
      expect(result.totalWeeks, isNull);
      expect(result.isSuccessful, isTrue);
    });
  });

  group('D. 端到端 parseJwxtWorkbook', () {
    final JwxtImportResult result = parseJwxtWorkbook(_realisticWorkbook());

    test('课程总数与学期三件套', () {
      expect(result.error, isNull);
      expect(result.skippedCount, 0);
      expect(result.courses, hasLength(6));
      expect(result.semesterName, '2026-2027年第1学期');
      expect(result.week1Monday, DateTime(2026, 8, 31));
      expect(result.totalWeeks, 20);
    });

    test('周一计算机网络：字段与 weekMask', () {
      final Course course = result.courses.firstWhere(
        (Course c) => c.name == '计算机网络',
      );
      expect(course.dayWeek, 1);
      expect(course.sectionStart, 3);
      expect(course.sectionEnd, 4);
      expect(
        weeksFromWeekMask(course.weekMask),
        {for (int i = 1; i <= 16; i++) i},
      );
    });

    test('周二分班多课：两条独立课程（军事理论 / 大学生创新教育Ⅰ）', () {
      expect(result.courses.where((Course c) => c.name == '军事理论').length, 1);
      expect(
        result.courses.where((Course c) => c.name == '大学生创新教育Ⅰ').length,
        1,
      );
      for (final Course c in result.courses) {
        if (c.name == '军事理论' || c.name == '大学生创新教育Ⅰ') {
          expect(c.dayWeek, 2);
          expect(weeksFromWeekMask(c.weekMask), <int>{11, 12, 13, 14});
        }
      }
    });

    test('单双周互补课（地点不同）→ 两条独立课程', () {
      final List<Course> math = result.courses
          .where((Course c) => c.name == '高等数学Ⅰ')
          .toList();
      expect(math, hasLength(2));
      final Set<int> masks = <int>{};
      for (final Course c in math) {
        expect(c.dayWeek, 3);
        masks.add(c.weekMask);
      }
      expect(masks, hasLength(2));
    });

    test('同格重复记录去重合并：数据结构 1-8周 + 9-16周 → 一门 1-16 周', () {
      final List<Course> ds = result.courses
          .where((Course c) => c.name == '数据结构')
          .toList();
      expect(ds, hasLength(1));
      expect(
        weeksFromWeekMask(ds.single.weekMask),
        {for (int i = 1; i <= 16; i++) i},
      );
    });

    test('找不到表头行 → 报错不抛', () {
      final JwxtImportResult bad = parseJwxtWorkbook(<List<String?>>[
        <String?>['随便', '什么'],
      ]);
      expect(bad.error, isNotNull);
      expect(bad.courses, isEmpty);
    });

    test('id 用 jw_ 前缀且不重复', () {
      final Set<String> ids = result.courses.map((Course c) => c.id).toSet();
      expect(ids, hasLength(result.courses.length));
      expect(ids.every((String id) => id.startsWith('jw_')), isTrue);
    });
  });
}

/// 最小可用工作表：表头 + 周一一格课 + 可选注释行。
List<List<String?>> _workbookWithNote(String? note) {
  final List<List<String?>> rows = <List<String?>>[
    <String?>['2026-2027年第1学期', null, null, '26软件3班'],
    <String?>['节次', null, '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    <String?>[null, '一', '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/(x)/y/80/ /'],
    <String?>[null, '二'],
    <String?>[null, '三'],
    <String?>[null, '四'],
    <String?>[null, '五'],
    <String?>['实践课程'],
    if (note != null) <String?>['注--：', note],
  ];
  return rows;
}

/// 仿真实导出结构（9 行 × 9 列口径）：
/// 周一 计算机网络；周二 分班两门；周三 单双周互补；周四 同格重复待合并。
List<List<String?>> _realisticWorkbook() {
  const String suffix = '(2026-2027-1)-10013C0002-20/26软件3班/90/ /';
  return <List<String?>>[
    <String?>['2026-2027年第1学期', null, null, '26卓越软件工程师3班'],
    <String?>['节次', null, '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    <String?>[null, '一', '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/$suffix'],
    <String?>[
      null,
      '二',
      null,
      '军事理论/(1-2节)11-14周/松山湖 松6-604/华康/$suffix'
          '\n大学生创新教育Ⅰ/(1-2节)11-14周/松山湖 松6-604/李四/$suffix',
    ],
    <String?>[
      null,
      '三',
      null,
      null,
      '高等数学Ⅰ/(1-2节)8-18周(双)/松山湖 松4-405/赵六/$suffix'
          '高等数学Ⅰ/(1-2节)8-18周(单)/松山湖 松4-406/赵六/$suffix',
    ],
    <String?>[
      null,
      '四',
      null,
      null,
      null,
      null,
      '数据结构/(5-6节)1-8周/松山湖 松5-501/王五/$suffix'
          '数据结构/(5-6节)9-16周/松山湖 松5-501/王五/$suffix',
    ],
    <String?>[null, '五'],
    <String?>['实践课程', null, null, null, null, null, null, null, null],
    <String?>['注--：', '本学期2026-08-31正式上课至2027-01-17结束，共20周.'],
  ];
}
