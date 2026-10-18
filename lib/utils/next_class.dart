/// 「下节课」小组件的候选列表纯函数，**不依赖 flutter**。
///
/// 候选覆盖未来若干天（当天 `end > now` 的节 + 之后几天），
/// 文案全部用**绝对时间**表述（`周一 10:25`），代码里禁止出现
/// 「今天 / 明天 / 后天」这类相对表述——相对表述会过期。
library;

import 'dart:convert';

import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_math.dart';

/// 一条「下节课」候选（未来某天某节的一门课）。
class NextCandidate {
  const NextCandidate({
    required this.title,
    required this.whenText,
    required this.endText,
    required this.location,
    required this.color,
    required this.start,
    required this.end,
  });

  /// 课程名。
  final String title;

  /// 绝对时间表述，如 `周一 10:25`（永不过期）。
  final String whenText;

  /// 下课时间，如 `12:00`（进行中时显示）。
  final String endText;

  /// 地点。
  final String location;

  /// 课程颜色，ARGB int 的**字符串**形式（Kotlin 侧 toLong 后再 toInt）。
  final String color;

  /// 开始的绝对时刻（**本地**时间，禁止 UTC）。
  final DateTime start;

  /// 结束的绝对时刻（本地时间）。
  final DateTime end;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'whenText': whenText,
      'endText': endText,
      'location': location,
      'color': color,
      'startMs': start.millisecondsSinceEpoch,
      'endMs': end.millisecondsSinceEpoch,
    };
  }

  /// 把候选列表序列化成 JSON 字符串（存 `next_items` 一个键）。
  static String encodeList(List<NextCandidate> candidates) {
    return jsonEncode(candidates.map((NextCandidate c) => c.toJson()).toList());
  }
}

/// 生成「下节课」候选列表：未来 [days] 天（默认 7 天）内 `end > now` 的全部节次。
///
/// 学期未配置 → 空列表。生成时已过滤已下课的节。
List<NextCandidate> nextCandidates(
  TimetableData data,
  DateTime now, {
  int days = 7,
}) {
  if (!data.semesterConfigured) {
    return <NextCandidate>[];
  }
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<NextCandidate> result = <NextCandidate>[];
  for (int offset = 0; offset < days; offset++) {
    final DateTime day = today.add(Duration(days: offset));
    final int week = weekOfDate(
      day,
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
    for (final CourseOccurrence occurrence in coursesForWeek(data, week)) {
      // 本周停课（cancelled override）不算候选
      if (occurrence.cancelled) {
        continue;
      }
      if (occurrence.dayWeek != day.weekday) {
        continue;
      }
      final Period? startPeriod = _periodAt(
        data.periods,
        occurrence.sectionStart,
      );
      final Period? endPeriod = _periodAt(data.periods, occurrence.sectionEnd);
      if (startPeriod == null || endPeriod == null) {
        continue;
      }
      // 修正 C：用本地 DateTime 构造，禁止 DateTime.utc（否则整体差 8 小时）
      final DateTime start = _at(day, startPeriod.start);
      final DateTime end = _at(day, endPeriod.end);
      if (!end.isAfter(now)) {
        continue;
      }
      result.add(
        NextCandidate(
          title: occurrence.course.name,
          whenText: '${_weekdayName(day.weekday)} ${startPeriod.start}',
          endText: endPeriod.end,
          location: occurrence.location,
          color: occurrence.course.colorValue.toString(),
          start: start,
          end: end,
        ),
      );
    }
  }
  result.sort((NextCandidate a, NextCandidate b) => a.start.compareTo(b.start));
  return result;
}

/// 生成 `scheduleWidgetUpdates` 的时刻清单：
/// 未来 [days] 天每天当地 00:00（跨天刷新）+ 每节课的 start 与 end 时刻
/// （上下课刷新）。
///
/// 过去时刻由 home_widget 忽略，这里直接过滤；调用方每次数据变化后
/// 重新设置即自动替换旧 schedule。
List<DateTime> widgetUpdateTimes(
  TimetableData data,
  DateTime now, {
  int days = 7,
}) {
  final DateTime today = DateTime(now.year, now.month, now.day);
  final List<DateTime> times = <DateTime>[];
  for (int offset = 0; offset <= days; offset++) {
    final DateTime day = today.add(Duration(days: offset));
    times.add(DateTime(day.year, day.month, day.day));
    for (final Period period in data.periods) {
      times.add(_at(day, period.start));
      times.add(_at(day, period.end));
    }
  }
  return times.where((DateTime time) => time.isAfter(now)).toList();
}

Period? _periodAt(List<Period> periods, int index) {
  for (final Period period in periods) {
    if (period.index == index) {
      return period;
    }
  }
  return null;
}

/// `HH:mm` + 日期 → 本地 DateTime（秒为 0）。
DateTime _at(DateTime day, String hhmm) {
  final List<String> parts = hhmm.split(':');
  final int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final int minute = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return DateTime(day.year, day.month, day.day, hour, minute, 0);
}

String _weekdayName(int weekday) {
  if (weekday < 1 || weekday > 7) {
    return '?';
  }
  return '周${'一二三四五六日'[weekday - 1]}';
}
