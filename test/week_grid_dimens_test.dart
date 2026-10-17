import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/theme/week_grid_dimens.dart';
import 'package:timetable/utils/breakpoints.dart';

/// 断点尺寸令牌与规格表逐项对照（值改动时这里会先红）。
void main() {
  group('WeekGridDimens.of 与规格表一致', () {
    test('compact（手机竖屏）', () {
      final WeekGridDimens d = WeekGridDimens.of(WindowSize.compact);
      expect(d.rowHeight, 56);
      expect(d.timeColumnWidth, 44);
      expect(d.headerHeight, 40);
      expect(d.sectionFontSize, 9);
      expect(d.timeFontSize, 8);
      expect(d.headerFontSize, 10);
      expect(d.courseNameSize, 11);
      expect(d.courseSubSize, 9);
      expect(d.badgeSize, 8);
    });

    test('medium（横屏 / 小平板）', () {
      final WeekGridDimens d = WeekGridDimens.of(WindowSize.medium);
      expect(d.rowHeight, 68);
      expect(d.timeColumnWidth, 52);
      expect(d.headerHeight, 46);
      expect(d.sectionFontSize, 10);
      expect(d.timeFontSize, 9);
      expect(d.headerFontSize, 11);
      expect(d.courseNameSize, 12);
      expect(d.courseSubSize, 10);
      expect(d.badgeSize, 9);
    });

    test('expanded（平板）', () {
      final WeekGridDimens d = WeekGridDimens.of(WindowSize.expanded);
      expect(d.rowHeight, 0);
      expect(d.timeColumnWidth, 64);
      expect(d.headerHeight, 54);
      expect(d.sectionFontSize, 12);
      expect(d.timeFontSize, 11);
      expect(d.headerFontSize, 13);
      expect(d.courseNameSize, 15);
      expect(d.courseSubSize, 12);
      expect(d.badgeSize, 11);
    });
  });

  test('expanded 的 rowHeight 为 0（表示按可用高度动态铺满）', () {
    expect(WeekGridDimens.of(WindowSize.expanded).rowHeight, 0);
  });

  test('compact / medium 的 rowHeight 为固定正值（不触发动态计算）', () {
    expect(WeekGridDimens.of(WindowSize.compact).rowHeight, greaterThan(0));
    expect(WeekGridDimens.of(WindowSize.medium).rowHeight, greaterThan(0));
  });
}
