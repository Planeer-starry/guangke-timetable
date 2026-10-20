import 'dart:io';
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/jwxt_table_importer.dart';
import 'package:timetable/utils/week_mask.dart';

/// 真实样本回归：test/fixtures/jwxt_jianghaoran.xlsx。
/// 用户 2026-10-20 主动提供（新版正方导出，三张工作表
/// 「课表 / 课程明细 / 说明」），授权入库做回归测试。
/// 「说明」表里声明「课程节次条目 31 条（含不同周次重复排课）」。
void main() {
  late final Excel excel;
  setUpAll(() async {
    final Uint8List bytes = await File('test/fixtures/jwxt_jianghaoran.xlsx')
        .readAsBytes();
    excel = await Excel.decodeBytesAsync(bytes);
  });

  List<List<String?>> rowsOf(String sheetName) => excel.tables[sheetName]!.rows
      .map(
        (List<dynamic> row) =>
            row.map((dynamic cell) => cell?.value?.toString()).toList(),
      )
      .toList();

  test('「课表」网格表：三行式单元格 + 三段式节次列', () {
    final JwxtImportResult result = parseJwxtWorkbook(rowsOf('课表'));
    expect(result.error, isNull);
    expect(result.skippedCount, 0);
    expect(result.fallbackCount, 0);

    // 三段式节次列（'1\n08:00\n08:40'）→ 构造出完整 15 节作息
    expect(result.periods, isNotNull);
    expect(result.usedDefaultPeriods, isFalse);
    final List<Period> periods = result.periods!;
    expect(periods, hasLength(15));
    expect(periods.first.index, 1);
    expect(periods.first.start, '08:00');
    expect(periods.first.end, '08:40');
    expect(periods.last.index, 15);
    expect(periods.last.start, '21:05');
    expect(periods.last.end, '21:45');

    // 三行式课程格：音乐鉴赏 周一 3-5 节 6-17 周
    final Course music = result.courses.firstWhere(
      (Course c) => c.name == '音乐鉴赏',
    );
    expect(music.dayWeek, 1);
    expect(music.sectionStart, 3);
    expect(music.sectionEnd, 5);
    expect(weeksFromWeekMask(music.weekMask), <int>{
      for (int i = 6; i <= 17; i++) i,
    });
    expect(music.location, '4-405');
    expect(music.teacher, '庄晨晖');

    // 空行分隔的多条目格：线性代数 周三 1-2（第16周）+ 1-3（6-15周）
    final List<Course> linear = result.courses
        .where((Course c) => c.name == '线性代数' && c.dayWeek == 3)
        .toList();
    expect(linear, hasLength(2));
    expect(
      linear
          .where((Course c) => c.sectionStart == 1 && c.sectionEnd == 2)
          .single
          .weekMask,
      1 << 15,
    );
    expect(
      weeksFromWeekMask(
        linear
            .where((Course c) => c.sectionStart == 1 && c.sectionEnd == 3)
            .single
            .weekMask,
      ),
      <int>{for (int i = 6; i <= 15; i++) i},
    );

    // 军事理论（三行式「第N周」单周）：周一第3/4周两个教师
    final List<Course> militaryMonday = result.courses
        .where((Course c) => c.name == '军事理论' && c.dayWeek == 1)
        .toList();
    expect(militaryMonday, hasLength(2));
    expect(militaryMonday.map((Course c) => c.teacher).toSet(), hasLength(2));

    // 学期名：标题挤着姓名学号，提取纯学期段
    expect(result.semesterName, '2026-2027学年第1学期');
    // week1Monday / totalWeeks 文件里没有 → null（不猜）
    expect(result.week1Monday, isNull);
    expect(result.totalWeeks, isNull);

    // 课程数与「说明」表声明的 31 条相差不超过 2
    expect((result.courses.length - 31).abs(), lessThanOrEqualTo(2));
    // 「其他课程」行（军事技能，无星期无节次）不进入课程
    expect(result.courses.any((Course c) => c.name.contains('军事技能')), isFalse);
  });

  test('「课程明细」逐条表：单独解析成功', () {
    final JwxtImportResult? detail = parseJwxtDetailTable(rowsOf('课程明细'));
    expect(detail, isNotNull);
    expect(detail!.isSuccessful, isTrue);
    expect((detail.courses.length - 31).abs(), lessThanOrEqualTo(2));
    // 明细表没有节次时间列 → periods 为 null（由多表择优互补）
    expect(detail.periods, isNull);
    expect(detail.semesterName, isNull);
  });

  test('多工作表择优：选中「课程明细」，作息与学期名从「课表」表互补', () {
    // 复刻 import_flow._importJwxtExcel 的择优逻辑（红线：择优留在 UI 层，
    // 测试以同构逻辑验证行为）
    final List<(JwxtImportResult, bool)> candidates =
        <(JwxtImportResult, bool)>[];
    final List<String> failures = <String>[];
    for (final Sheet sheet in excel.tables.values) {
      final List<List<String?>> rows = sheet.rows
          .map(
            (List<dynamic> row) =>
                row.map((dynamic cell) => cell?.value?.toString()).toList(),
          )
          .toList();
      final JwxtImportResult? detail = parseJwxtDetailTable(rows);
      final JwxtImportResult result = detail ?? parseJwxtWorkbook(rows);
      if (result.isSuccessful) {
        candidates.add((result, detail != null));
      } else if (result.error != null) {
        failures.add(result.error!);
      }
    }

    // 三张表：「课表」与「课程明细」成功，「说明」失败（无课表表头）
    expect(candidates, hasLength(2));
    expect(failures, hasLength(1));

    // 择优：课程数打平（都是 31）→ 逐条表优先
    (JwxtImportResult, bool) best = candidates.first;
    for (final (JwxtImportResult, bool) candidate in candidates.skip(1)) {
      final bool better;
      if (candidate.$1.courses.length != best.$1.courses.length) {
        better = candidate.$1.courses.length > best.$1.courses.length;
      } else if (candidate.$2 != best.$2) {
        better = candidate.$2;
      } else {
        better = candidate.$1.skippedCount < best.$1.skippedCount;
      }
      if (better) {
        best = candidate;
      }
    }
    expect(best.$2, isTrue, reason: '课程数打平时应选中逐条表结果');
    expect((best.$1.courses.length - 31).abs(), lessThanOrEqualTo(2));

    // 主结果字段合法性
    for (final Course course in best.$1.courses) {
      expect(course.name, isNotEmpty);
      expect(course.sectionStart, lessThanOrEqualTo(course.sectionEnd));
      expect(course.weekMask, isNot(0));
      expect(course.dayWeek, inInclusiveRange(1, 7));
    }

    // 防止「weekMask 全 20 周全满」的旧 bug（1048575 = 0xFFFFF）
    final int fullMask = weekMaskFromWeeks(<int>{
      for (int i = 1; i <= 20; i++) i,
    });
    expect(best.$1.courses.any((Course c) => c.weekMask != fullMask), isTrue);

    // 互补：作息 / 学期名缺失时从其它成功表补
    final List<Period>? periods =
        best.$1.periods ?? _firstPeriodsOf(candidates);
    expect(periods, isNotNull);
    expect(periods!.length, greaterThanOrEqualTo(10));
    final String? semesterName =
        best.$1.semesterName ?? _firstSemesterNameOf(candidates);
    expect(semesterName, '2026-2027学年第1学期');
  });
}

/// 与 import_flow._firstPeriodsOf 同构（互补逻辑的测试复刻）。
List<Period>? _firstPeriodsOf(List<(JwxtImportResult, bool)> candidates) {
  for (final (JwxtImportResult result, _) in candidates) {
    if (result.periods != null && result.periods!.isNotEmpty) {
      return result.periods;
    }
  }
  return null;
}

/// 与 import_flow._firstSemesterNameOf 同构（互补逻辑的测试复刻）。
String? _firstSemesterNameOf(List<(JwxtImportResult, bool)> candidates) {
  for (final (JwxtImportResult result, _) in candidates) {
    if (result.semesterName != null && result.semesterName!.isNotEmpty) {
      return result.semesterName;
    }
  }
  return null;
}
