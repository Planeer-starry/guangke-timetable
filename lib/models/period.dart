/// 节次时间：一节课的序号与起止时间。
///
/// 对应 JSON 契约 `periods[].{index,start,end}`（见 AGENTS.md 5.2）。
class Period {
  const Period({required this.index, required this.start, required this.end});

  /// 节次序号，从 1 开始。
  final int index;

  /// 开始时间，格式 `HH:mm`。
  final String start;

  /// 结束时间，格式 `HH:mm`。
  final String end;

  /// 防御式解析：字段缺失或类型不符时回退到默认值，绝不抛异常。
  factory Period.fromJson(Map<String, dynamic> json) {
    return Period(
      index: (json['index'] as int?) ?? 0,
      start: (json['start'] as String?) ?? '',
      end: (json['end'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'index': index, 'start': start, 'end': end};
  }

  /// 广科真实作息（共 10 节），直接作为默认值。
  static const List<Period> defaults = <Period>[
    Period(index: 1, start: '08:30', end: '09:15'),
    Period(index: 2, start: '09:20', end: '10:05'),
    Period(index: 3, start: '10:25', end: '11:10'),
    Period(index: 4, start: '11:15', end: '12:00'),
    Period(index: 5, start: '14:40', end: '15:25'),
    Period(index: 6, start: '15:30', end: '16:15'),
    Period(index: 7, start: '16:30', end: '17:15'),
    Period(index: 8, start: '17:20', end: '18:05'),
    Period(index: 9, start: '19:30', end: '20:15'),
    Period(index: 10, start: '20:20', end: '21:05'),
  ];
}
