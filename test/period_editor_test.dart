import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/period_editor.dart';

/// 作息编辑纯函数（J10）：时间解析 / 追加 / 删除 / 平移 / 校验 / 摘要。
void main() {
  group('minutesOf', () {
    test('正常解析', () {
      expect(minutesOf('08:30'), 8 * 60 + 30);
      expect(minutesOf('00:00'), 0);
      expect(minutesOf('23:59'), 1439);
    });

    test("'9:5' 之类的非严格格式失败", () {
      expect(minutesOf('9:5'), isNull);
      expect(minutesOf('9:05'), isNull);
      expect(minutesOf('0830'), isNull);
      expect(minutesOf(''), isNull);
    });

    test('时 / 分越界失败', () {
      expect(minutesOf('24:00'), isNull);
      expect(minutesOf('08:60'), isNull);
    });
  });

  group('hhmmOf', () {
    test('正常 + 补零', () {
      expect(hhmmOf(510), '08:30');
      expect(hhmmOf(0), '00:00');
      expect(hhmmOf(61), '01:01');
    });

    test('负数 clamp 到 00:00', () {
      expect(hhmmOf(-30), '00:00');
    });

    test('超 1439 clamp 到 23:59', () {
      expect(hhmmOf(1500), '23:59');
    });
  });

  group('addPeriod', () {
    test('末尾追加：start = 上节 end + 10、时长 45', () {
      final List<Period> one = <Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
      ];
      final List<Period> two = addPeriod(one);
      expect(two.length, 2);
      expect(two[1].index, 2);
      expect(two[1].start, '09:25');
      expect(two[1].end, '10:10');
    });

    test('跨天：end 超 23:59 时 clamp 到 23:55', () {
      final List<Period> late = <Period>[
        const Period(index: 1, start: '22:00', end: '23:30'),
      ];
      final List<Period> added = addPeriod(late);
      expect(added.length, 2);
      expect(added[1].start, '23:40');
      expect(added[1].end, '23:55');
    });

    test('上一节结束太晚（塞不下）则不加', () {
      final List<Period> full = <Period>[
        const Period(index: 1, start: '23:00', end: '23:55'),
      ];
      expect(addPeriod(full).length, 1);
    });

    test('已达 24 节时不增', () {
      final List<Period> many = List<Period>.generate(
        24,
        (int i) => Period(index: i + 1, start: '08:00', end: '08:45'),
      );
      expect(addPeriod(many).length, 24);
    });
  });

  group('removeLastPeriod', () {
    test('正常减一', () {
      final List<Period> two = <Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
        const Period(index: 2, start: '09:20', end: '10:05'),
      ];
      final List<Period> one = removeLastPeriod(two);
      expect(one.length, 1);
      expect(one[0].index, 1);
    });

    test('只剩 1 节时不变', () {
      final List<Period> one = <Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
      ];
      expect(removeLastPeriod(one).length, 1);
    });
  });

  group('shiftAll', () {
    test('+10 正常平移', () {
      final List<Period> shifted = shiftAll(<Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
      ], 10);
      expect(shifted[0].start, '08:40');
      expect(shifted[0].end, '09:25');
    });

    test('-10 正常平移', () {
      final List<Period> shifted = shiftAll(<Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
      ], -10);
      expect(shifted[0].start, '08:20');
      expect(shifted[0].end, '09:05');
    });

    test('早于 00:00 的部分 clamp 到 00:00', () {
      final List<Period> shifted = shiftAll(<Period>[
        const Period(index: 1, start: '00:05', end: '00:50'),
      ], -10);
      expect(shifted[0].start, '00:00');
      expect(shifted[0].end, '00:40');
    });

    test('晚于 23:59 的部分 clamp 到 23:59', () {
      final List<Period> shifted = shiftAll(<Period>[
        const Period(index: 1, start: '23:15', end: '23:50'),
      ], 20);
      expect(shifted[0].start, '23:35');
      expect(shifted[0].end, '23:59');
    });

    test('平移后 start >= end 的那一节保持原值', () {
      // 00:00-00:05 平移 -10：两端都夹到 00:00（start == end），保持原值
      final List<Period> shifted = shiftAll(<Period>[
        const Period(index: 1, start: '08:30', end: '09:15'),
        const Period(index: 2, start: '00:00', end: '00:05'),
      ], -10);
      expect(shifted[0].start, '08:20');
      expect(shifted[0].end, '09:05');
      expect(shifted[1].start, '00:00');
      expect(shifted[1].end, '00:05');
    });
  });

  group('validatePeriods', () {
    test('空列表 -> 数量错误', () {
      expect(validatePeriods(<Period>[]), '节次数量需在 1~24 之间');
    });

    test('25 节 -> 数量错误', () {
      final List<Period> many = List<Period>.generate(
        25,
        (int i) => Period(index: i + 1, start: '08:00', end: '08:45'),
      );
      expect(validatePeriods(many), '节次数量需在 1~24 之间');
    });

    test('index 不连续 -> 节次序错误', () {
      final List<Period> bad = <Period>[
        const Period(index: 1, start: '08:00', end: '08:45'),
        const Period(index: 3, start: '09:00', end: '09:45'),
      ];
      expect(validatePeriods(bad), '节次序需要连续');
    });

    test('start >= end -> 第 N 节结束时间错误', () {
      expect(
        validatePeriods(<Period>[
          const Period(index: 1, start: '09:00', end: '09:00'),
        ]),
        '第 1 节的结束时间必须晚于开始时间',
      );
    });

    test('格式错 -> HH:mm 错误', () {
      expect(
        validatePeriods(<Period>[
          const Period(index: 1, start: '9:00', end: '09:45'),
        ]),
        '第 1 节的时间格式不是 HH:mm',
      );
    });

    test('默认作息合法 -> null', () {
      expect(validatePeriods(Period.defaults), isNull);
    });
  });

  group('periodsSummary', () {
    test('默认作息摘要', () {
      expect(periodsSummary(Period.defaults), '10 节 · 08:30–21:05');
    });

    test('空列表', () {
      expect(periodsSummary(<Period>[]), '0 节');
    });
  });
}
