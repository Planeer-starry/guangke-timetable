import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/utils/week_mask.dart';

void main() {
  group('weekMaskFromWeeks', () {
    test('空集合 → mask 为 0', () {
      expect(weekMaskFromWeeks(<int>[]), 0);
    });

    test('第 1 周 → 1', () {
      expect(weekMaskFromWeeks(<int>[1]), 1);
    });

    test('第 20 周 → 1 << 19', () {
      expect(weekMaskFromWeeks(<int>[20]), 1 << 19);
    });

    test('第 32 周（边界）→ 1 << 31', () {
      expect(weekMaskFromWeeks(<int>[32]), 1 << 31);
    });

    test('越界周次被忽略', () {
      expect(weekMaskFromWeeks(<int>[0, 33, 1]), 1);
    });
  });

  group('hasClassInWeek', () {
    test('命中与不命中', () {
      final int mask = weekMaskFromWeeks(<int>[1, 3, 5]);
      expect(hasClassInWeek(mask, 1), isTrue);
      expect(hasClassInWeek(mask, 2), isFalse);
      expect(hasClassInWeek(mask, 3), isTrue);
      expect(hasClassInWeek(mask, 5), isTrue);
    });

    test('第 0 周、第 33 周安全处理，不抛异常且为 false', () {
      expect(hasClassInWeek(0xFFFFFFFF, 0), isFalse);
      expect(hasClassInWeek(0xFFFFFFFF, 33), isFalse);
    });
  });

  group('weeksFromWeekMask', () {
    test('mask ↔ weeks 往返一致', () {
      final List<int> weeks = <int>[1, 2, 16, 20, 32];
      expect(weeksFromWeekMask(weekMaskFromWeeks(weeks)), weeks);
    });

    test('0xFFFF 对应 1..16', () {
      expect(
        weeksFromWeekMask(0xFFFF),
        List<int>.generate(16, (int i) => i + 1),
      );
    });

    test('mask 为 0 → 空列表', () {
      expect(weeksFromWeekMask(0), isEmpty);
    });
  });
}
