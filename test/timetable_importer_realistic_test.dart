import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/timetable_importer.dart';

/// 用「真实广科教务导出格式」驱动的端到端回归测试。
///
/// 输入形如外部 Python 脚本产出的 timetable.json：
///   { "1": [ {...}, ... ], "2": [...], ..., "20": [...] }
/// 覆盖：连堂、单双周、字段别名混用、jcs 范围写法、无效条目跳过。
void main() {
  /// 生成某门课在指定周的条目。
  Map<String, dynamic> entryFor({
    required String name,
    required Object section,
    required int dayWeek,
    required int week,
    String teacher = '张三',
    String location = '教学楼A101',
    bool useZhengfangAlias = false,
  }) {
    if (useZhengfangAlias) {
      // 正方原始字段名
      return <String, dynamic>{
        'kcmc': name,
        'xm': teacher,
        'jxdd': location,
        'jcs': section,
        'xqj': dayWeek,
        'week': week,
      };
    }
    return <String, dynamic>{
      'courseName': name,
      'teacher': teacher,
      'classroomName': location,
      'whichSection': section,
      'dayWeek': dayWeek,
      'week': week,
    };
  }

  test('真实 20 周数据：两级聚合端到端正确', () {
    // 每门课：(名称, 节次, dayWeek, 教师, 地点, 上课周次集合, 是否用正方别名)
    final List<(String, Object, int, String, String, Set<int>, bool)>
    courses = <(String, Object, int, String, String, Set<int>, bool)>[
      (
        '计算机网络',
        3,
        1,
        '张明',
        '教学楼A302',
        <int>{for (int w = 1; w <= 16; w++) w},
        false,
      ),
      (
        '操作系统',
        5,
        1,
        '李红',
        '教学楼B201',
        <int>{for (int w = 1; w <= 8; w++) w},
        false,
      ),
      (
        '高等数学',
        1,
        2,
        '王强',
        '实验楼C101',
        <int>{for (int w = 1; w <= 16; w++) w},
        false,
      ),
      ('大学英语', 3, 2, '陈静', '逸夫楼D203', <int>{2, 4, 6, 8, 10, 12, 14, 16}, false),
      // 正方写法：jcs = "3-4" 必须展开成第 3、4 节（连堂）
      (
        '数据结构',
        '3-4',
        3,
        '刘伟',
        '计算机楼E101',
        <int>{for (int w = 1; w <= 16; w++) w},
        true,
      ),
      ('体育', 7, 3, '赵磊', '田径场', <int>{1, 3, 5, 7, 9, 11, 13, 15}, false),
    ];

    // 连堂课的第 4 节（除数据结构用 jcs 范围外，其余手工补一条）
    final Map<int, List<Map<String, dynamic>>> byWeek =
        <int, List<Map<String, dynamic>>>{};
    for (int week = 1; week <= 20; week++) {
      byWeek[week] = <Map<String, dynamic>>[];
    }
    for (final c in courses) {
      for (final int week in c.$6) {
        byWeek[week]!.add(
          entryFor(
            name: c.$1,
            section: c.$2,
            dayWeek: c.$3,
            week: week,
            teacher: c.$4,
            location: c.$5,
            useZhengfangAlias: c.$7,
          ),
        );
        // 连堂：非 jcs 范围的课，补第二个节次
        if (c.$2 is int && c.$1 != '操作系统' && c.$1 != '体育' && c.$1 != '高等数学') {
          byWeek[week]!.add(
            entryFor(
              name: c.$1,
              section: (c.$2 as int) + 1,
              dayWeek: c.$3,
              week: week,
              teacher: c.$4,
              location: c.$5,
            ),
          );
        }
      }
    }
    // 两个无效条目：dayWeek 越界、缺课程名
    byWeek[1]!.add(<String, dynamic>{
      'courseName': '越界课',
      'dayWeek': 9,
      'whichSection': 1,
    });
    byWeek[1]!.add(<String, dynamic>{'dayWeek': 1, 'whichSection': 1});

    final Map<String, dynamic> root = <String, dynamic>{
      for (final e in byWeek.entries) '${e.key}': e.value,
    };

    final ImportResult result = parseImportedTimetable(root);

    // ── 基本统计 ──
    expect(result.error, isNull, reason: '不应报错');
    expect(result.courses.length, 6, reason: '应识别出 6 门课');
    expect(result.skippedCount, 2, reason: '两条无效条目应被跳过');

    Course find(String name) =>
        result.courses.firstWhere((Course c) => c.name == name);

    // ── 连堂合并 ──
    final Course net = find('计算机网络');
    expect(net.sectionStart, 3);
    expect(net.sectionEnd, 4, reason: '3、4 节是连堂，应合并');
    expect(
      net.weekMask,
      weekMaskFromWeeks(<int>{for (int w = 1; w <= 16; w++) w}),
      reason: '1-16 周 → 0xFFFF',
    );

    // ── 正方 jcs 范围写法必须展开成连堂 ──
    final Course ds = find('数据结构');
    expect(ds.sectionStart, 3);
    expect(ds.sectionEnd, 4, reason: 'jcs="3-4" 必须展开成第 3、4 节连堂');

    // ── 单周 / 双周 ──
    final Course english = find('大学英语');
    expect(weeksFromWeekMask(english.weekMask), <int>[
      2,
      4,
      6,
      8,
      10,
      12,
      14,
      16,
    ], reason: '双周');
    final Course pe = find('体育');
    expect(weeksFromWeekMask(pe.weekMask), <int>[
      1,
      3,
      5,
      7,
      9,
      11,
      13,
      15,
    ], reason: '单周');

    // ── 字段别名（正方写法）解析正确 ──
    expect(ds.teacher, '刘伟');
    expect(ds.location, '计算机楼E101');
    expect(ds.dayWeek, 3);

    // ── id 唯一 ──
    final Set<String> ids = result.courses.map((Course c) => c.id).toSet();
    expect(ids.length, 6, reason: 'id 必须唯一');
  });

  test('App 自己导出的格式要被识别并报错', () {
    final ImportResult result = parseImportedTimetable(<String, dynamic>{
      'schema': 1,
      'meta': <String, dynamic>{},
      'periods': <dynamic>[],
      'courses': <dynamic>[],
    });
    expect(result.error, isNotNull);
    expect(result.courses, isEmpty);
  });

  test('空对象返回空列表且不崩', () {
    final ImportResult result = parseImportedTimetable(<String, dynamic>{});
    expect(result.courses, isEmpty);
  });
}
