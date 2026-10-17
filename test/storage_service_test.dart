import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/storage_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('timetable_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  StorageService newService() => StorageService(directory: tempDir);

  String filePath() =>
      '${tempDir.path}${Platform.pathSeparator}${StorageService.fileName}';

  TimetableData sampleData({String courseName = '计算机网络'}) {
    return TimetableData.fromJson(<String, dynamic>{
      'schema': 1,
      'meta': <String, dynamic>{
        'school': '广东科技学院',
        'semesterName': '2026-2027 第一学期',
        'week1Monday': '2026-09-07',
        'totalWeeks': 20,
      },
      'courses': <dynamic>[
        <String, dynamic>{
          'id': 'c_001',
          'name': courseName,
          'teacher': '张三',
          'location': '教学楼A101',
          'colorValue': 4294198070,
          'dayWeek': 1,
          'sectionStart': 3,
          'sectionEnd': 4,
          'weekMask': 65535,
          'note': '',
        },
      ],
    });
  }

  group('StorageService.load', () {
    test('文件不存在 → 返回空课表，不抛异常', () async {
      final TimetableData data = await newService().load();
      expect(data.courses, isEmpty);
      expect(data.periods.length, 10);
    });

    test('合法 JSON → 解析正确', () async {
      await File(filePath()).writeAsString(jsonEncode(sampleData().toJson()));

      final TimetableData data = await newService().load();

      expect(data.meta.week1Monday, DateTime(2026, 9, 7));
      expect(data.courses.single.name, '计算机网络');
    });

    test('损坏 JSON → 返回空课表、不抛异常，并保留 .corrupt 备份', () async {
      await File(filePath()).writeAsString('{broken json');

      final TimetableData data = await newService().load();

      expect(data.courses, isEmpty);
      expect(await File(filePath()).exists(), isFalse);
      final List<File> files = (await tempDir.list().toList())
          .whereType<File>()
          .toList();
      expect(files.any((File f) => f.path.contains('.corrupt.')), isTrue);
    });

    test('顶层不是 JSON 对象 → 返回空课表并保留 .corrupt 备份', () async {
      await File(filePath()).writeAsString('[1,2,3]');

      final TimetableData data = await newService().load();

      expect(data.courses, isEmpty);
      final List<File> files = (await tempDir.list().toList())
          .whereType<File>()
          .toList();
      expect(files.any((File f) => f.path.contains('.corrupt.')), isTrue);
    });
  });

  group('StorageService.save', () {
    test('保存后读回相同内容', () async {
      final StorageService service = newService();

      await service.save(sampleData());

      final TimetableData loaded = await service.load();
      expect(loaded.meta.week1Monday, DateTime(2026, 9, 7));
      expect(loaded.courses.single.name, '计算机网络');
    });

    test('对同一路径连续 save 两次 → 读回为第二次内容，且不残留 .tmp/.bak', () async {
      final StorageService service = newService();

      await service.save(sampleData(courseName: '计算机网络'));
      await service.save(sampleData(courseName: '高等数学'));

      final TimetableData loaded = await service.load();
      expect(loaded.courses.single.name, '高等数学');

      final List<String> names = (await tempDir.list().toList())
          .map((FileSystemEntity e) => e.path)
          .toList();
      expect(names.any((String p) => p.endsWith('.tmp')), isFalse);
      expect(names.any((String p) => p.endsWith('.bak')), isFalse);
    });
  });
}
