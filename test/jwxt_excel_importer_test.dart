import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
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
      expect(weeksFromWeekMask(course.weekMask), {
        for (int i = 1; i <= 16; i++) i,
      });
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
      expect(weeksFromWeekMask(ds.single.weekMask), {
        for (int i = 1; i <= 16; i++) i,
      });
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

  group('E. 表头两级识别', () {
    test('表头写「周一..周日」→ 能定位表头', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['2026-2027年第1学期'],
        <String?>['节次', null, '周一', '周二', '周三', '周四', '周五', '周六', '周日'],
        <String?>[null, '一', '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/x/y/90/ /'],
      ]);
      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.dayWeek, 1);
    });

    test('表头只有周一到周五 → 只解析 5 列，不崩', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三', '周四', '周五'],
        <String?>[
          null,
          '一',
          null,
          null,
          null,
          null,
          '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/x/y/90/ /',
        ],
      ]);
      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.dayWeek, 5);
    });

    test('表头第一级命中 < 3 → 启用裸字回退定位', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        // 裸字表头：'一' 在索引 1，因此课程也要放在索引 1 才是星期一
        <String?>['节', '一', '二', '三', '四', '五', '六', '日'],
        <String?>[
          null,
          '计算机网络/(3-4节)1-16周/松山湖 松3-302/张三/x/y/90/ /',
        ],
      ]);
      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.dayWeek, 1);
    });

    test('裸字也不足 3 个 → 仍找不到表头', () {
      final JwxtImportResult bad = parseJwxtWorkbook(<List<String?>>[
        <String?>['项目', '一', '二'],
      ]);
      expect(bad.error, isNotNull);
      expect(bad.courses, isEmpty);
    });
  });

  group('F. 节次行推断与作息三态', () {
    test('节次列 ["1","2","3"] → detectedSectionCount=3，periods=null', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>['1', null, '课A/(1-2节)1-16周/楼/师/x/y/90/ /'],
        <String?>['2'],
        <String?>['3'],
      ]);
      expect(result.error, isNull);
      expect(result.detectedSectionCount, 3);
      expect(result.periods, isNull);
      expect(result.usedDefaultPeriods, isTrue);
    });

    test(
      '节次列 ["1\\n08:00-08:45", ...] → periods 构造、usedDefaultPeriods=false',
      () {
        final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
          <String?>['学期'],
          <String?>['节次', null, '周一', '周二', '周三'],
          <String?>['1\n08:00-08:45', null, '课A/(1-2节)1-16周/楼/师/x/y/90/ /'],
          <String?>['2\n08:55-09:40'],
        ]);
        expect(result.usedDefaultPeriods, isFalse);
        expect(result.periods, isNotNull);
        expect(result.periods!.map((Period p) => p.index), <int>[1, 2]);
        expect(result.periods!.first.start, '08:00');
        expect(result.periods!.first.end, '08:45');
        expect(result.periods!.last.start, '08:55');
        expect(result.periods!.last.end, '09:40');
      },
    );

    test('节次列汉字数字读不到编号 → periods=null、usedDefaultPeriods=true', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>['一', null, '课A/(1-2节)1-16周/楼/师/x/y/90/ /'],
        <String?>['二'],
        <String?>['三'],
      ]);
      expect(result.periods, isNull);
      expect(result.usedDefaultPeriods, isTrue);
      // 汉字读不到 → 按物理行序递增，3 个非空数据行 → 3
      expect(result.detectedSectionCount, 3);
    });

    test('格内无节次 → 用行标签推断（第 2 层条目）', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>['1'],
        <String?>['3', null, '高等数学\n张三\n1-16周\n教1-201'],
      ]);
      expect(result.error, isNull);
      expect(result.courses, hasLength(1));
      final Course course = result.courses.single;
      expect(course.name, '高等数学');
      expect(course.sectionStart, 3);
      expect(course.sectionEnd, 3);
      expect(course.dayWeek, 1);
      expect(weeksFromWeekMask(course.weekMask), {
        for (int i = 1; i <= 16; i++) i,
      });
    });
  });

  group('G. E1 绝对校验（不与行推断节数挂钩）', () {
    test('8 节表格 + 格内 (9-10节) → 不被节次上界误杀', () {
      final List<List<String?>> rows = <List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>['1', null, '晚课/(9-10节)1-16周/楼/师/x/y/90/ /'],
        for (int i = 2; i <= 8; i++) <String?>['$i'],
      ];
      final JwxtImportResult result = parseJwxtWorkbook(rows);
      expect(result.error, isNull);
      expect(result.detectedSectionCount, 8);
      expect(result.courses, hasLength(1));
      expect(result.courses.single.sectionStart, 9);
      expect(result.courses.single.sectionEnd, 10);
    });

    test('行推断只能得 5 的表，格内 (1-2)..(9-10) 全部保留', () {
      const String suffix = '/x/y/90/ /';
      final List<List<String?>> rows = <List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>[null, '一', '课一/(1-2节)1-16周/楼/师$suffix'],
        <String?>[null, '二', '课二/(3-4节)1-16周/楼/师$suffix'],
        <String?>[null, '三', '课三/(5-6节)1-16周/楼/师$suffix'],
        <String?>[null, '四', '课四/(7-8节)1-16周/楼/师$suffix'],
        <String?>[null, '五', '课五/(9-10节)1-16周/楼/师$suffix'],
      ];
      final JwxtImportResult result = parseJwxtWorkbook(rows);
      expect(result.error, isNull);
      expect(result.skippedCount, 0);
      expect(result.courses, hasLength(5));
      expect(result.detectedSectionCount, 5);
      expect(result.courses.map((Course c) => c.sectionStart), <int>[
        1,
        3,
        5,
        7,
        9,
      ]);
      expect(result.courses.map((Course c) => c.sectionEnd), <int>[
        2,
        4,
        6,
        8,
        10,
      ]);
    });
  });

  group('H. 第 2/3 层接入', () {
    test('第 1 层未命中 → 第 2 层接管（青果多课锚点切分）', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>[
          '3',
          null,
          '军事理论\n张三\n11-14周\n松6-604\n高等数学\n李四\n1-16周\n教1-201',
        ],
      ]);
      expect(result.error, isNull);
      expect(result.fallbackCount, 0);
      expect(result.courses, hasLength(2));
      final Course first = result.courses.firstWhere(
        (Course c) => c.name == '军事理论',
      );
      expect(first.teacher, '张三');
      expect(first.location, '松6-604');
      expect(first.sectionStart, 3);
      expect(first.sectionEnd, 3);
      expect(weeksFromWeekMask(first.weekMask), <int>{11, 12, 13, 14});
      final Course second = result.courses.firstWhere(
        (Course c) => c.name == '高等数学',
      );
      expect(second.teacher, '李四');
      expect(second.location, '教1-201');
      expect(second.sectionStart, 3);
      expect(weeksFromWeekMask(second.weekMask), {
        for (int i = 1; i <= 16; i++) i,
      });
    });

    test('第 3 层兜底：fallbackCount 计数、周次填全部周', () {
      final JwxtImportResult result = parseJwxtWorkbook(<List<String?>>[
        <String?>['学期'],
        <String?>['节次', null, '周一', '周二', '周三'],
        <String?>['2', null, '1-16周\n教1-201'],
      ]);
      expect(result.error, isNull);
      expect(result.fallbackCount, 1);
      expect(result.courses, hasLength(1));
      final Course course = result.courses.single;
      expect(course.name, '1-16周 教1-201');
      expect(course.sectionStart, 2);
      expect(course.sectionEnd, 2);
      // 无 totalWeeks 元信息 → 全部周按缺省上界 20 填
      expect(weeksFromWeekMask(course.weekMask), {
        for (int i = 1; i <= 20; i++) i,
      });
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
