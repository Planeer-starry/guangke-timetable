import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/next_class.dart';

/// 构造一份已配置的课表：第一周周一 2026-09-07，20 周，默认 10 节作息。
TimetableData buildData({
  List<Map<String, dynamic>> courses = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> overrides = const <Map<String, dynamic>>[],
}) {
  return TimetableData.fromJson(<String, dynamic>{
    'schema': 1,
    'meta': <String, dynamic>{
      'school': '广东科技学院',
      'semesterName': '测试学期',
      'week1Monday': '2026-09-07',
      'totalWeeks': 20,
    },
    'courses': courses,
    'overrides': overrides,
  });
}

Map<String, dynamic> course({
  String id = 'c_001',
  String name = '计算机网络',
  int dayWeek = 1,
  int sectionStart = 3,
  int sectionEnd = 4,
  int weekMask = 0xFFFFFFFF,
  int colorValue = 4294198070,
  String location = '教学楼A302',
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'teacher': '张三',
    'location': location,
    'colorValue': colorValue,
    'dayWeek': dayWeek,
    'sectionStart': sectionStart,
    'sectionEnd': sectionEnd,
    'weekMask': weekMask,
    'note': '',
  };
}

void main() {
  // 固定「现在」：2026-09-09（周三）11:30 —— 第 3 节（10:25-11:10）刚下课，
  // 第 4 节（11:15-12:00）正在进行。
  final DateTime now = DateTime(2026, 9, 9, 11, 30);

  group('nextCandidates', () {
    test('学期未配置 → 空候选', () {
      expect(nextCandidates(TimetableData.empty(), now), isEmpty);
    });

    test('本周停课（cancelled override）的课不出现在候选里', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 3, sectionStart: 4, sectionEnd: 4),
        ],
        overrides: <Map<String, dynamic>>[
          <String, dynamic>{
            'courseId': 'c_001',
            'week': 1,
            'dayWeek': 3,
            'sectionStart': 4,
            'sectionEnd': 4,
            'location': '教学楼A302',
            'cancelled': true,
          },
        ],
      );

      // now 是第 1 周周三，该课本该在候选里；停课后 → 空
      expect(nextCandidates(data, now), isEmpty);
    });

    test('进行中的节出现在候选里，whenText 用绝对时间', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 3, sectionStart: 4, sectionEnd: 4),
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      expect(candidates, isNotEmpty);
      expect(candidates.first.title, '计算机网络');
      expect(candidates.first.whenText, '周三 11:15');
      expect(candidates.first.endText, '12:00');
      expect(
        candidates.first.start.millisecondsSinceEpoch,
        DateTime(2026, 9, 9, 11, 15).millisecondsSinceEpoch,
      );
    });

    test('已下课的节（end <= now）不进候选', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 3, sectionStart: 1, sectionEnd: 1),
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      expect(candidates, isEmpty);
    });

    test('今天课上完 → 候选是之后几天的节', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(
            id: 'c_009',
            name: '周四第一节',
            dayWeek: 4,
            sectionStart: 1,
            sectionEnd: 1,
          ),
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      expect(candidates.first.whenText, '周四 08:30');
    });

    test('周末跨到下周一', () {
      final DateTime saturday = DateTime(2026, 9, 12, 12, 0);
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[course(dayWeek: 1)],
      );

      final List<NextCandidate> candidates = nextCandidates(data, saturday);

      expect(candidates.first.whenText, '周一 10:25');
    });

    test('weekMask 该周无课 → 该天无候选', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[course(dayWeek: 3, weekMask: 0x1)],
      );

      // 2026-09-16 是第 2 周周三
      final DateTime week2Wednesday = DateTime(2026, 9, 16, 11, 30);
      expect(nextCandidates(data, week2Wednesday), isEmpty);
    });

    test('override 生效：时段地点被替换', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[course(dayWeek: 3)],
        overrides: <Map<String, dynamic>>[
          <String, dynamic>{
            'courseId': 'c_001',
            'week': 1,
            'dayWeek': 5,
            'sectionStart': 5,
            'sectionEnd': 6,
            'location': '实验楼B203',
          },
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      expect(candidates.first.whenText, '周五 14:40');
      expect(candidates.first.location, '实验楼B203');
    });

    test('候选按 start 升序', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(
            id: 'c_002',
            name: '上午的课',
            dayWeek: 3,
            sectionStart: 1,
            sectionEnd: 1,
          ),
          course(
            id: 'c_003',
            name: '下午的课',
            dayWeek: 3,
            sectionStart: 5,
            sectionEnd: 5,
          ),
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      expect(candidates.first.title, '下午的课');
    });

    test('候选不使用相对表述（无「今天/明天/后天」字样）', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 3),
          course(id: 'c_004', name: '明天见', dayWeek: 4),
        ],
      );

      final List<NextCandidate> candidates = nextCandidates(data, now);

      for (final NextCandidate candidate in candidates) {
        expect(candidate.whenText.contains('今天'), isFalse);
        expect(candidate.whenText.contains('明天'), isFalse);
        expect(candidate.whenText.contains('后天'), isFalse);
      }
    });
  });

  group('NextCandidate.encodeList', () {
    test('color 超过 Kotlin Int.MAX 时序列化不丢精度', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 1, colorValue: 4294198070),
        ],
      );

      final DateTime mondayMorning = DateTime(2026, 9, 7, 8, 0);
      final String json = NextCandidate.encodeList(
        nextCandidates(data, mondayMorning),
      );

      expect(json.contains('"color":"4294198070"'), isTrue);
    });

    test('序列化包含 startMs / endMs', () {
      final TimetableData data = buildData(
        courses: <Map<String, dynamic>>[
          course(dayWeek: 3, sectionStart: 4, sectionEnd: 4),
        ],
      );

      final String json = NextCandidate.encodeList(nextCandidates(data, now));

      expect(json, contains('"startMs"'));
      expect(json, contains('"endMs"'));
      expect(json, contains('"whenText":"周三 11:15"'));
    });
  });

  group('widgetUpdateTimes', () {
    test('含每天 00:00 与每节课 start/end，且全部在未来', () {
      final TimetableData data = buildData();

      final List<DateTime> times = widgetUpdateTimes(data, now);

      expect(times, isNotEmpty);
      expect(times.every((DateTime time) => time.isAfter(now)), isTrue);
      expect(times.contains(DateTime(2026, 9, 10)), isTrue);
      expect(times.contains(DateTime(2026, 9, 9, 12, 0)), isTrue);
      expect(times.contains(DateTime(2026, 9, 10, 8, 30)), isTrue);
    });

    test('过去时刻被丢弃', () {
      final TimetableData data = buildData();

      final List<DateTime> times = widgetUpdateTimes(data, now);

      expect(times.contains(DateTime(2026, 9, 9)), isFalse);
      expect(times.contains(DateTime(2026, 9, 9, 8, 30)), isFalse);
    });
  });
}
