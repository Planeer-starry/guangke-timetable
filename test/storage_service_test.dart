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

  String snapshotFilePath() =>
      '${tempDir.path}${Platform.pathSeparator}'
      '${StorageService.snapshotFileName}';

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

  group('导入快照（saveImportedSnapshot / loadImportedSnapshot）', () {
    test('saveImportedSnapshot 后 hasImportedSnapshot == true', () async {
      final StorageService service = newService();

      await service.saveImportedSnapshot(sampleData());

      expect(await service.hasImportedSnapshot(), isTrue);
    });

    test('loadImportedSnapshot 返回内容与保存的一致', () async {
      final StorageService service = newService();

      await service.saveImportedSnapshot(sampleData(courseName: '大学物理'));

      final TimetableData? loaded = await service.loadImportedSnapshot();
      expect(loaded, isNotNull);
      expect(loaded!.courses.single.name, '大学物理');
      expect(loaded.meta.week1Monday, DateTime(2026, 9, 7));
    });

    test(
      '无快照时 hasImportedSnapshot == false，loadImportedSnapshot 返回 null',
      () async {
        final StorageService service = newService();

        expect(await service.hasImportedSnapshot(), isFalse);
        expect(await service.loadImportedSnapshot(), isNull);
      },
    );

    test('快照文件损坏（非法 JSON）→ loadImportedSnapshot 返回 null 不抛', () async {
      await File(snapshotFilePath()).writeAsString('{broken json');
      final StorageService service = newService();

      final TimetableData? loaded = await service.loadImportedSnapshot();

      expect(loaded, isNull);
    });

    test('连续覆盖快照 → 读回为最新，且不残留 .tmp/.bak、不影响主文件', () async {
      final StorageService service = newService();
      await service.save(sampleData(courseName: '主文件课'));

      await service.saveImportedSnapshot(sampleData(courseName: '第一次导入'));
      await service.saveImportedSnapshot(sampleData(courseName: '第二次导入'));

      final TimetableData? snapshot = await service.loadImportedSnapshot();
      expect(snapshot!.courses.single.name, '第二次导入');
      // 主文件不受快照写入影响
      final TimetableData main = await service.load();
      expect(main.courses.single.name, '主文件课');

      final List<String> names = (await tempDir.list().toList())
          .map((FileSystemEntity e) => e.path)
          .toList();
      expect(names.any((String p) => p.endsWith('.tmp')), isFalse);
      expect(names.any((String p) => p.endsWith('.bak')), isFalse);
    });
  });
}
