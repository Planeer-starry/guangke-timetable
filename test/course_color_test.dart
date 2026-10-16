import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/utils/course_color.dart';

void main() {
  group('colorValueFromName', () {
    test('同名课程颜色稳定', () {
      expect(colorValueFromName('计算机网络'), colorValueFromName('计算机网络'));
    });

    test('结果落在调色板内', () {
      expect(coursePalette.contains(colorValueFromName('高等数学')), isTrue);
      expect(coursePalette.contains(colorValueFromName('大学英语')), isTrue);
    });

    test('空字符串安全处理', () {
      expect(colorValueFromName(''), coursePalette.first);
    });

    test('不同课程名可得到不同颜色', () {
      final Set<int> colors = <int>{
        colorValueFromName('计算机网络'),
        colorValueFromName('高等数学'),
        colorValueFromName('大学英语'),
        colorValueFromName('体育'),
      };
      expect(colors.length, greaterThan(1));
    });
  });
}
