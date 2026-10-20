import 'dart:io';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/jwxt_table_importer.dart';
import 'package:timetable/utils/week_mask.dart';

/// 真实样本：test/fixtures/jwxt_jianghaoran.xlsx。
/// 用户 2026-10-20 主动提供（新版正方导出，含「课表 / 课程明细 / 说明」
/// 三张工作表），授权入库做回归测试。本文件测「课程明细」逐条表解析。
void main() {
  late final List<List<String?>> detailRows;
  setUpAll(() async {
    final Uint8List bytes = await File('test/fixtures/jwxt_jianghaoran.xlsx')
        .readAsBytes();
    final Excel excel = await Excel.decodeBytesAsync(bytes);
    final Sheet sheet = excel.tables['课程明细']!;
    detailRows = sheet.rows
        .map(
          (List<dynamic> row) =>
              row.map((dynamic cell) => cell?.value?.toString()).toList(),
        )
        .toList();
  });

  group('真实样本「课程明细」表', () {
    test('识别为逐条表：非 null、成功、课程数 >= 20', () {
      final JwxtImportResult? result = parseJwxtDetailTable(detailRows);
      expect(result, isNotNull);
      expect(result!.isSuccessful, isTrue);
      expect(result.courses.length, greaterThanOrEqualTo(20));
      expect(result.skippedCount, 0);
    });

    test('音乐鉴赏：星期一 3-5 节 6-17 周 4-405 庄晨晖', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      final Course course = result.courses.firstWhere(
        (Course c) => c.name == '音乐鉴赏',
      );
      expect(course.dayWeek, 1);
      expect(course.sectionStart, 3);
      expect(course.sectionEnd, 5);
      expect(course.location, '4-405');
      expect(course.teacher, '庄晨晖');
    });

    test('「6-17周」区间：mask 的 6..17 位为 1，其余为 0', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      final Course course = result.courses.firstWhere(
        (Course c) => c.name == '音乐鉴赏',
      );
      expect(
        course.weekMask,
        weekMaskFromWeeks(<int>{for (int i = 6; i <= 17; i++) i}),
      );
      expect(hasClassInWeek(course.weekMask, 5), isFalse);
      expect(hasClassInWeek(course.weekMask, 18), isFalse);
    });

    test('「第16周」单周写法：线性代数 星期三 1-2 节', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      final Course course = result.courses.firstWhere(
        (Course c) =>
            c.name == '线性代数' && c.sectionStart == 1 && c.sectionEnd == 2,
      );
      expect(course.dayWeek, 3);
      expect(course.teacher, '邓若瑜');
      expect(course.weekMask, 1 << 15);
    });

    test('「第2/3/4周」单周：军事理论 6 条、不跨教师合并', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      final List<Course> military = result.courses
          .where((Course c) => c.name == '军事理论')
          .toList();
      // 6 条记录（每周不同教师是真实排课，跨教师合并会丢信息）
      expect(military, hasLength(6));
      expect(military.map((Course c) => c.teacher).toSet(), hasLength(6));
      // 周次只有第 2/3/4 周，绝不出现「全 20 周全满」
      expect(military.map((Course c) => c.weekMask).toSet(), <int>{
        1 << 1,
        1 << 2,
        1 << 3,
      });
    });

    test('「第7周」单周：大学英语(一)B1班 星期一 6-7 节', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      final Course course = result.courses.firstWhere(
        (Course c) =>
            c.name == '大学英语(一)B1班' && c.dayWeek == 1 && c.sectionStart == 6,
      );
      expect(course.weekMask, 1 << 6);
    });

    test('字段完整性：每门课各字段合法', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      for (final Course c in result.courses) {
        expect(c.name, isNotEmpty);
        expect(c.sectionStart, lessThanOrEqualTo(c.sectionEnd));
        expect(c.dayWeek, inInclusiveRange(1, 7));
        expect(c.weekMask, isNot(0));
        // 明细表场地/教师列都有值（「未排地点」也算原文非空）
        expect(c.location, isNotEmpty);
        expect(c.teacher, isNotEmpty);
      }
    });

    test('学期与作息：文件里没有 → null（不猜）', () {
      final JwxtImportResult result = parseJwxtDetailTable(detailRows)!;
      // 表头在第 1 行，之前没有标题行 → 学期名也拿不到
      expect(result.semesterName, isNull);
      expect(result.week1Monday, isNull);
      expect(result.totalWeeks, isNull);
      expect(result.periods, isNull);
      expect(result.usedDefaultPeriods, isTrue);
    });
  });

  group('纯逻辑（不读文件）', () {
    test('表头列序变化仍能定位（按表头文字，不写死列号）', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['序号', '课程名称', '周次', '教师', '星期', '节次', '场地'],
        <String?>['1', '测试课', '第3周', '张三', '周三', '2-4', 'A101'],
      ]);
      expect(result, isNotNull);
      final Course course = result!.courses.single;
      expect(course.name, '测试课');
      expect(course.dayWeek, 3);
      expect(course.sectionStart, 2);
      expect(course.sectionEnd, 4);
      expect(weeksFromWeekMask(course.weekMask), <int>{3});
      expect(course.teacher, '张三');
      expect(course.location, 'A101');
    });

    test('同 key 周次取并集合并', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['课程名称', '星期', '节次', '周次', '场地', '教师'],
        <String?>['测试课', '星期一', '1-2', '1-8周', 'A101', '张三'],
        <String?>['测试课', '星期一', '1-2', '10-16周', 'A101', '张三'],
      ]);
      expect(result, isNotNull);
      expect(result!.courses, hasLength(1));
      expect(weeksFromWeekMask(result.courses.single.weekMask), <int>{
        for (int i = 1; i <= 8; i++) i,
        for (int i = 10; i <= 16; i++) i,
      });
    });

    test('不同教师不合并（同课同格同节次）', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['课程名称', '星期', '节次', '周次', '场地', '教师'],
        <String?>['军事理论', '星期一', '4-6', '第3周', '未排地点', '张佩怡'],
        <String?>['军事理论', '星期一', '4-6', '第4周', '未排地点', '蒋慧新'],
      ]);
      expect(result, isNotNull);
      expect(result!.courses, hasLength(2));
      expect(result.courses.map((Course c) => c.teacher).toSet(), hasLength(2));
    });

    test('周次空集的行跳过并计入 skippedCount', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['课程名称', '星期', '节次', '周次', '场地', '教师'],
        <String?>['好课', '星期一', '1-2', '1-8周', 'A101', '张三'],
        <String?>['坏课', '星期一', '1-2', '第?周', 'A101', '张三'],
      ]);
      expect(result, isNotNull);
      expect(result!.courses, hasLength(1));
      expect(result.courses.single.name, '好课');
      expect(result.skippedCount, 1);
    });

    test('缺必需列（无周次列表头）→ null', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['序号', '课程名称', '星期', '节次', '教师'],
        <String?>['1', '测试课', '星期一', '2-4', '张三'],
      ]);
      expect(result, isNull);
    });

    test('网格课表表头（无「课程名」列）→ null', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['2026-2027学年第1学期'],
        <String?>['时间段', '节次', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
        <String?>['上午', '1\n08:00\n08:40'],
      ]);
      expect(result, isNull);
    });

    test('表头行之前有标题行 → 提取学期名（去姓名学号）', () {
      final JwxtImportResult? result = parseJwxtDetailTable(<List<String?>>[
        <String?>['2026-2027学年第1学期  江浩然课表    学号：xxx'],
        <String?>['序号', '课程名称', '星期', '节次', '周次', '场地', '教师'],
        <String?>['1', '测试课', '星期一', '2-4', '第3周', 'A101', '张三'],
      ]);
      expect(result, isNotNull);
      expect(result!.semesterName, '2026-2027学年第1学期');
    });
  });
}
