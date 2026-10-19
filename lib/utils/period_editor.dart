/// 作息时间编辑的纯函数层（J10）。
///
/// 全部无状态、不依赖 flutter，方便单测；
/// UI 层（作息设置页 / 时间选择面板）只做交互与提交。
library;

import 'package:timetable/models/period.dart';

/// 严格的 `HH:mm` 格式（两位数字 + 冒号 + 两位数字）。
final RegExp _hhmmPattern = RegExp(r'^\d{2}:\d{2}$');

/// `HH:mm` -> 当天第几分钟（0..1439）；格式或范围非法返回 null。
int? minutesOf(String hhmm) {
  if (!_hhmmPattern.hasMatch(hhmm)) {
    return null;
  }
  final int hour = int.parse(hhmm.substring(0, 2));
  final int minute = int.parse(hhmm.substring(3));
  if (hour > 23 || minute > 59) {
    return null;
  }
  return hour * 60 + minute;
}

/// 当天第几分钟 -> `HH:mm`；自动 clamp 到 0..1439。
String hhmmOf(int minutes) {
  final int clamped = minutes < 0 ? 0 : (minutes > 1439 ? 1439 : minutes);
  return '${(clamped ~/ 60).toString().padLeft(2, '0')}:'
      '${(clamped % 60).toString().padLeft(2, '0')}';
}

/// 末尾追加一节：start = 上一节 end + 10 分钟，时长 45 分钟。
///
/// - 节次上限 24，已达上限返回原列表；
/// - 新节 end 超过 23:59 时 clamp 到 23:55 结束；
/// - 上一节时间非法、或 clamp 后 start >= end（当天塞不下）返回原列表。
List<Period> addPeriod(List<Period> periods) {
  if (periods.length >= 24) {
    return periods;
  }
  if (periods.isEmpty) {
    return const <Period>[Period(index: 1, start: '08:30', end: '09:15')];
  }
  final Period last = periods.last;
  final int? lastEnd = minutesOf(last.end);
  if (lastEnd == null) {
    return periods;
  }
  final int start = (lastEnd + 10).clamp(0, 1439);
  final int end = start + 45 > 1439 ? 1435 : start + 45;
  if (start >= end) {
    return periods;
  }
  return <Period>[
    ...periods,
    Period(index: periods.length + 1, start: hhmmOf(start), end: hhmmOf(end)),
  ];
}

/// 删除最后一节。至少保留 1 节（只有 1 节时返回原列表）。
List<Period> removeLastPeriod(List<Period> periods) {
  if (periods.length <= 1) {
    return periods;
  }
  return periods.sublist(0, periods.length - 1);
}

/// 整体平移 [deltaMinutes] 分钟（可为负）。
///
/// 逐节 clamp 到 00:00..23:59；平移后 start >= end 的那一节**保持原值**
/// （时长远小于平移量的早课 / 晚课会被双向夹死，与其变非法不如不动）。
List<Period> shiftAll(List<Period> periods, int deltaMinutes) {
  final List<Period> result = <Period>[];
  for (final Period period in periods) {
    final int? start = minutesOf(period.start);
    final int? end = minutesOf(period.end);
    if (start == null || end == null) {
      result.add(period);
      continue;
    }
    final int shiftedStart = (start + deltaMinutes).clamp(0, 1439);
    final int shiftedEnd = (end + deltaMinutes).clamp(0, 1439);
    if (shiftedStart >= shiftedEnd) {
      result.add(period);
      continue;
    }
    result.add(
      Period(
        index: period.index,
        start: hhmmOf(shiftedStart),
        end: hhmmOf(shiftedEnd),
      ),
    );
  }
  return result;
}

/// 校验，返回错误文案或 null（合法）：
/// - 数量不在 1..24     -> 「节次数量需在 1~24 之间」
/// - index 不是连续 1..N -> 「节次序需要连续」
/// - 某一节 start >= end -> 「第 N 节的结束时间必须晚于开始时间」
/// - start/end 解析失败  -> 「第 N 节的时间格式不是 HH:mm」
String? validatePeriods(List<Period> periods) {
  if (periods.isEmpty || periods.length > 24) {
    return '节次数量需在 1~24 之间';
  }
  for (int i = 0; i < periods.length; i++) {
    if (periods[i].index != i + 1) {
      return '节次序需要连续';
    }
  }
  for (final Period period in periods) {
    final int? start = minutesOf(period.start);
    final int? end = minutesOf(period.end);
    if (start == null || end == null) {
      return '第 ${period.index} 节的时间格式不是 HH:mm';
    }
    if (start >= end) {
      return '第 ${period.index} 节的结束时间必须晚于开始时间';
    }
  }
  return null;
}

/// 摘要文案：`10 节 · 08:30–21:05`（破折号用 – U+2013）。
String periodsSummary(List<Period> periods) {
  if (periods.isEmpty) {
    return '0 节';
  }
  return '${periods.length} 节 · ${periods.first.start}–${periods.last.end}';
}
