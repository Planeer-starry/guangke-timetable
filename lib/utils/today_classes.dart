import 'dart:convert';

import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_math.dart';

/// 「今日课程」小组件的一节课（纯展示数据，由 Dart 算好）。
class TodayItem {
  const TodayItem({
    required this.timeText,
    required this.title,
    required this.location,
    required this.color,
  });

  /// 起止时间，如 `08:30-10:05`。
  final String timeText;

  /// 课程名。
  final String title;

  /// 地点。
  final String location;

  /// 课程色（ARGB int）。
  final int color;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'timeText': timeText,
    'title': title,
    'location': location,
    // Kotlin Int 是 32 位：先转字符串，Kotlin 侧 toLong 再 toInt 保位模式
    'color': color.toString(),
  };
}

/// 「今日课程」小组件的一天分组（Kotlin 按日期挑出今天这组渲染）。
class TodayGroup {
  const TodayGroup({
    required this.date,
    required this.header,
    required this.items,
  });

  /// 本地日期（零点）。
  final DateTime date;

  /// 表头文案，如 `10月17日 周六 · 第6周`（绝对日期，禁止「今天/明天」）。
  final String header;

  /// 当天课程，按节次升序。
  final List<TodayItem> items;

  /// 与 Kotlin `LocalDate.now().toString()` 对齐的日期键：`2026-10-17`。
  String get dateKey =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'date': dateKey,
    'header': header,
    'items': items.map((TodayItem item) => item.toJson()).toList(),
  };

  /// 序列化整组列表，存进 home_widget 的 `today_days` 键。
  static String encodeList(List<TodayGroup> groups) {
    return jsonEncode(
      groups.map((TodayGroup group) => group.toJson()).toList(),
    );
  }
}

/// 生成 [now] 起 [days] 天的「今日课程」分组（纯函数，供单测）。
///
/// 为什么存 7 天分组而不是只存今天：跨天 0 点触发的是 Android 的
/// onUpdate，不会重新跑 Dart；存分组后 Kotlin 每次 onUpdate 都用
/// 当天日期挑组，跨天自动正确（与「下节课」的候选列表同一思路）。
/// 周次、override 均已生效（复用 weekOfDate + coursesForWeek）。
List<TodayGroup> todayGroups(TimetableData data, DateTime now, {int days = 7}) {
  if (!data.semesterConfigured) {
    return const <TodayGroup>[];
  }
  final List<TodayGroup> result = <TodayGroup>[];
  final DateTime today = DateTime(now.year, now.month, now.day);
  for (int i = 0; i < days; i++) {
    final DateTime date = today.add(Duration(days: i));
    final int week = weekOfDate(
      date,
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
    final List<CourseOccurrence> dayCourses =
        coursesForWeek(
            data,
            week,
          ).where((CourseOccurrence o) => o.dayWeek == date.weekday).toList()
          ..sort(
            (CourseOccurrence a, CourseOccurrence b) =>
                a.sectionStart.compareTo(b.sectionStart),
          );
    result.add(
      TodayGroup(
        date: date,
        header: _headerText(date, week),
        items: <TodayItem>[
          for (final CourseOccurrence o in dayCourses)
            TodayItem(
              timeText: _timeText(data.periods, o.sectionStart, o.sectionEnd),
              title: o.course.name,
              location: o.location,
              color: o.course.colorValue,
            ),
        ],
      ),
    );
  }
  return result;
}

const List<String> _dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

String _headerText(DateTime date, int week) {
  return '${date.month}月${date.day}日 周${_dayNames[date.weekday - 1]} · 第$week周';
}

/// 起止时间文案；节次越界（防御脏数据）回退为「第N-M节」。
String _timeText(List<Period> periods, int sectionStart, int sectionEnd) {
  if (sectionStart < 1 ||
      sectionEnd < sectionStart ||
      sectionEnd > periods.length) {
    return '第$sectionStart-$sectionEnd节';
  }
  return '${periods[sectionStart - 1].start}-${periods[sectionEnd - 1].end}';
}
