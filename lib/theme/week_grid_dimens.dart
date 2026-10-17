import 'package:timetable/utils/breakpoints.dart';

/// 周视图网格的断点尺寸令牌。
///
/// compact = 手机竖屏 / medium = 横屏与小平板 / expanded = 平板。
/// 所有字段由 [of] 按断点给出，WeekGrid / CourseBlock 不再有任何硬编码尺寸。
///
/// [rowHeight] 为 0 表示「按可用高度动态算」（仅 expanded）：
/// 由 WeekGrid 内部的 LayoutBuilder 用
/// `(可用高度 - 表头) / 节数` 计算，clamp 到 64~100。
class WeekGridDimens {
  const WeekGridDimens({
    required this.rowHeight,
    required this.timeColumnWidth,
    required this.headerHeight,
    required this.sectionFontSize,
    required this.timeFontSize,
    required this.headerFontSize,
    required this.courseNameSize,
    required this.courseSubSize,
    required this.badgeSize,
  });

  /// 每一节的高度；0 = expanded 动态铺满。
  final double rowHeight;

  /// 左侧节次列宽。
  final double timeColumnWidth;

  /// 表头高度。
  final double headerHeight;

  /// 节次序号字号。
  final double sectionFontSize;

  /// 节次开始/结束时间字号。
  final double timeFontSize;

  /// 表头日期字号。
  final double headerFontSize;

  /// 课程块课名字号。
  final double courseNameSize;

  /// 课程块地点（或「地点 · 教师」）行字号。
  final double courseSubSize;

  /// 「+N」角标字号。
  final double badgeSize;

  /// 按断点返回尺寸令牌。
  factory WeekGridDimens.of(WindowSize size) {
    switch (size) {
      case WindowSize.expanded:
        return const WeekGridDimens(
          rowHeight: 0,
          timeColumnWidth: 64,
          headerHeight: 54,
          sectionFontSize: 12,
          timeFontSize: 11,
          headerFontSize: 13,
          courseNameSize: 15,
          courseSubSize: 12,
          badgeSize: 11,
        );
      case WindowSize.medium:
        return const WeekGridDimens(
          rowHeight: 68,
          timeColumnWidth: 52,
          headerHeight: 46,
          sectionFontSize: 10,
          timeFontSize: 9,
          headerFontSize: 11,
          courseNameSize: 12,
          courseSubSize: 10,
          badgeSize: 9,
        );
      case WindowSize.compact:
        return const WeekGridDimens(
          rowHeight: 56,
          timeColumnWidth: 44,
          headerHeight: 40,
          sectionFontSize: 9,
          timeFontSize: 8,
          headerFontSize: 10,
          courseNameSize: 11,
          courseSubSize: 9,
          badgeSize: 8,
        );
    }
  }
}
