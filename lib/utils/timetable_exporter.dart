/// 课表导出（J11）：把 [TimetableData] 序列化为简课表备份 JSON。
///
/// 纯函数、不依赖 flutter，方便单测。
/// 导出的文件在「导入」时会被完整恢复：学期、作息、课程与当周调整。
library;

import 'dart:convert';

import 'package:timetable/models/timetable_data.dart';

/// 导出为缩进 2 的 JSON 字符串。
///
/// 顶层含 schema / meta / periods / courses / overrides 五个键，
/// 换手机时把字符串存成 .json 再导入即可完整搬迁。
String exportTimetableJson(TimetableData data) {
  return const JsonEncoder.withIndent('  ').convert(data.toJson());
}
