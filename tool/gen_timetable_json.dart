// 开发辅助脚本：把「按周展开」的教务 JSON 转成 App 的存储格式 timetable.json。
//
// 用途：真机测试时快速构造数据，或在数据被清空后恢复。
// 用法：dart run tool/gen_timetable_json.dart <输入 json> <输出 json> [week1Monday]
//
// 注意：本脚本只在电脑上跑，不参与 App 运行时。
import 'dart:convert';
import 'dart:io';

import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/timetable_importer.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/gen_timetable_json.dart <输入> <输出> [week1Monday]');
    exit(2);
  }
  final String input = args[0];
  final String output = args[1];
  final String week1 = args.length > 2 ? args[2] : '2026-09-07';

  final Object? decoded = jsonDecode(File(input).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('输入不是 JSON 对象');
    exit(1);
  }
  final ImportResult result = parseImportedTimetable(decoded);
  if (!result.isSuccessful) {
    stderr.writeln('解析失败: ${result.error}');
    exit(1);
  }

  final TimetableData data = TimetableData(
    meta: TimetableMeta(
      school: '广东科技学院',
      semesterName: '2026-2027 第一学期',
      week1Monday: DateTime.parse(week1),
      totalWeeks: 20,
    ),
    periods: Period.defaults,
    courses: result.courses,
    overrides: const <CourseOverride>[],
  );

  File(output).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(data.toJson()),
  );
  stdout.writeln(
    '✅ 课程 ${result.courses.length} 门，跳过 ${result.skippedCount} 条 → $output',
  );
  for (final course in result.courses.take(5)) {
    stdout.writeln('   · ${course.name} 周${course.dayWeek} '
        '第${course.sectionStart}-${course.sectionEnd}节 '
        'weeks=${course.weekMask}');
  }
}
