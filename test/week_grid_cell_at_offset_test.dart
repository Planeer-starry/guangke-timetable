import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/widgets/week_grid.dart';

/// cellAtOffset 纯函数测试：坐标 → (星期, 节次)。
void main() {
  const double timeColumnWidth = 48;
  const double dayColumnWidth = 100;
  const double rowHeight = 64;
  const int periods = 10;

  (int, int) at(Offset offset) {
    return WeekGrid.cellAtOffset(
      offset,
      timeColumnWidth: timeColumnWidth,
      dayColumnWidth: dayColumnWidth,
      rowHeight: rowHeight,
      periods: periods,
    );
  }

  test('Offset(0,0) → (1,1)', () {
    expect(at(const Offset(0, 0)), (1, 1));
  });

  test('Offset(60,10) → (1,1)（节次列内、首行内）', () {
    expect(at(const Offset(60, 10)), (1, 1));
  });

  test('Offset(160,10) → (2,1)（第二列首行）', () {
    expect(at(const Offset(160, 10)), (2, 1));
  });

  test('Offset(360,140) → (4,3)（普通中段坐标）', () {
    expect(at(const Offset(360, 140)), (4, 3));
  });

  test('Offset(9999,0) → (7,1)（水平越界 clamp 到周日）', () {
    expect(at(const Offset(9999, 0)), (7, 1));
  });

  test('Offset(60,9999) → (1,10)（垂直越界 clamp 到最后一节）', () {
    expect(at(const Offset(60, 9999)), (1, 10));
  });

  test('负坐标 clamp 到 (1,1)，不抛异常', () {
    expect(at(const Offset(-500, -500)), (1, 1));
  });
}