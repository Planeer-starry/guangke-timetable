// 开发辅助：用真实教务 .xls 文件验证完整导入管线（不含 UI）。
//
// 用法：dart run tool/verify_jwxt_xls.dart <xls 路径>
//
// 验证链路：excel_plus 解码 .xls → parseJwxtWorkbook 解析 → 打印课程与元信息。
// 这个脚本不参与 App 运行时，也不放进 test/（避免依赖外部文件导致别人跑不过）。
import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/week_math.dart';
import 'package:timetable/utils/week_mask.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法: dart run tool/verify_jwxt_xls.dart <xls 路径>');
    exit(2);
  }
  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('文件不存在: ${args[0]}');
    exit(1);
  }
  stdout.writeln('文件: ${file.path}');
  stdout.writeln('大小: ${file.lengthSync()} 字节');

  final Excel excel = await Excel.decodeBytesAsync(file.readAsBytesSync());
  final Sheet sheet = excel.tables.values.first;
  final List<List<String?>> rows = sheet.rows
      .map(
        (List<Data?> row) =>
            row.map((Data? cell) => cell?.value?.toString()).toList(),
      )
      .toList();
  stdout.writeln('工作表: ${excel.tables.keys.first}  行=${rows.length}');

  final JwxtImportResult result = parseJwxtWorkbook(rows);
  stdout.writeln('');
  stdout.writeln('══════════ 解析结果 ══════════');
  if (result.error != null) {
    stdout.writeln('❌ error: ${result.error}');
    exit(1);
  }
  stdout.writeln('课程数    : ${result.courses.length}');
  stdout.writeln('跳过      : ${result.skippedCount}');
  stdout.writeln('学期名    : ${result.semesterName}');
  stdout.writeln('第一周周一: ${result.week1Monday}');
  stdout.writeln('总周数    : ${result.totalWeeks}');
  stdout.writeln('');
  stdout.writeln('══════════ 课程列表 ══════════');
  const List<String> dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];
  for (final Course c in result.courses) {
    final String weeks = formatWeekRanges(weeksFromWeekMask(c.weekMask));
    stdout.writeln(
      '${c.id.padRight(7)} 周${dayNames[c.dayWeek - 1]} '
      '第${c.sectionStart}-${c.sectionEnd}节  '
      '${c.name.padRight(18)} $weeks  '
      '${c.location}  ${c.teacher}  mask=${c.weekMask}',
    );
  }

  // 交叉校验：不连续周次与单双周
  stdout.writeln('');
  stdout.writeln('══════════ 关键周次校验 ══════════');
  for (final Course c in result.courses) {
    final List<int> w = weeksFromWeekMask(c.weekMask);
    if (w.length != (w.last - w.first + 1)) {
      stdout.writeln('  不连续: ${c.name} → $w');
    }
  }
}
