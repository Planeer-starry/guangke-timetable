import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/utils/week_math.dart';

void main() {
  final DateTime week1Monday = DateTime(2026, 9, 7);

  group('weekOfDate', () {
    test('第一周周一 → 第 1 周', () {
      expect(weekOfDate(DateTime(2026, 9, 7), week1Monday, 20), 1);
    });

    test('第一周周日仍属第 1 周', () {
      expect(weekOfDate(DateTime(2026, 9, 13), week1Monday, 20), 1);
    });

    test('第二周周一 → 第 2 周', () {
      expect(weekOfDate(DateTime(2026, 9, 14), week1Monday, 20), 2);
    });

    test('忽略时间部分，只看日期', () {
      expect(weekOfDate(DateTime(2026, 9, 14, 23, 59), week1Monday, 20), 2);
    });

    test('开学之前 clamp 到 1', () {
      expect(weekOfDate(DateTime(2026, 8, 1), week1Monday, 20), 1);
    });

    test('学期结束后 clamp 到 totalWeeks', () {
      expect(weekOfDate(DateTime(2027, 6, 1), week1Monday, 20), 20);
    });
  });

  group('mondayOfWeek', () {
    test('第 1 周周一即 week1Monday', () {
      expect(mondayOfWeek(week1Monday, 1), week1Monday);
    });

    test('第 3 周周一', () {
      expect(mondayOfWeek(week1Monday, 3), DateTime(2026, 9, 21));
    });
  });
}
