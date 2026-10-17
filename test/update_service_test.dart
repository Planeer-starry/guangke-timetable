import 'package:flutter_test/flutter_test.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/services/update_service.dart';

/// 构造一条合法的 UpdateInfo，只覆盖需要变化的字段。
UpdateInfo _info({
  int versionCode = 2,
  int minSupportedVersionCode = 1,
  String packageName = 'com.planeer.timetable',
}) {
  return UpdateInfo(
    schema: 1,
    platform: 'android',
    packageName: packageName,
    versionName: '1.0.1',
    versionCode: versionCode,
    minSupportedVersionCode: minSupportedVersionCode,
    sha256: 'a' * 64,
    size: 56000000,
    releasedAt: null,
    releaseNotes: const <String>['修复若干问题'],
    downloadUrl: 'https://example.com/app-release.apk',
  );
}

void main() {
  group('evaluateUpdate（纯函数）', () {
    test('versionCode 更高 → 返回更新信息', () {
      final UpdateInfo? result = UpdateService.evaluateUpdate(
        _info(versionCode: 2),
        1,
        'com.planeer.timetable',
      );
      expect(result, isNotNull);
      expect(result!.versionCode, 2);
    });

    test('versionCode 相同 → 无更新', () {
      expect(
        UpdateService.evaluateUpdate(
          _info(versionCode: 2),
          2,
          'com.planeer.timetable',
        ),
        isNull,
      );
    });

    test('versionCode 更低 → 无更新（服务器版本回滚的场景）', () {
      expect(
        UpdateService.evaluateUpdate(
          _info(versionCode: 1),
          2,
          'com.planeer.timetable',
        ),
        isNull,
      );
    });

    test('packageName 不符 → null（防止装错包）', () {
      expect(
        UpdateService.evaluateUpdate(
          _info(packageName: 'com.other.app'),
          1,
          'com.planeer.timetable',
        ),
        isNull,
      );
    });

    test('versionCode 更高但 packageName 不符 → 依然 null', () {
      expect(
        UpdateService.evaluateUpdate(
          _info(versionCode: 99, packageName: 'com.other.app'),
          1,
          'com.planeer.timetable',
        ),
        isNull,
      );
    });
  });

  group('强制更新判定', () {
    test('minSupportedVersionCode 高于当前 → 强制', () {
      expect(_info(minSupportedVersionCode: 5).isForceUpdateFor(4), isTrue);
    });

    test('minSupportedVersionCode 等于当前 → 不强制', () {
      expect(_info(minSupportedVersionCode: 4).isForceUpdateFor(4), isFalse);
    });

    test('minSupportedVersionCode 低于当前 → 不强制', () {
      expect(_info(minSupportedVersionCode: 1).isForceUpdateFor(4), isFalse);
    });
  });

  group('UpdateInfo.fromJson（防御式解析，绝不抛异常）', () {
    test('完整字段全部解析正确', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'schema': 1,
        'platform': 'android',
        'packageName': 'com.planeer.timetable',
        'versionName': '1.0.1',
        'versionCode': 2,
        'minSupportedVersionCode': 1,
        'sha256': 'b' * 64,
        'size': 1024,
        'releasedAt': '2026-10-01T00:00:00Z',
        'releaseNotes': <String>['修复 A', '优化 B'],
        'downloadUrl': 'https://example.com/app-release.apk',
      };
      final UpdateInfo info = UpdateInfo.fromJson(json);
      expect(info.schema, 1);
      expect(info.versionName, '1.0.1');
      expect(info.versionCode, 2);
      expect(info.minSupportedVersionCode, 1);
      expect(info.size, 1024);
      expect(info.releasedAt, isNotNull);
      expect(info.releaseNotes, <String>['修复 A', '优化 B']);
    });

    test('空对象 → 全部默认值，不抛异常', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{});
      expect(info.schema, 1);
      expect(info.platform, 'android');
      expect(info.packageName, '');
      expect(info.versionName, '');
      expect(info.versionCode, 0);
      expect(info.minSupportedVersionCode, 0);
      expect(info.sha256, '');
      expect(info.size, 0);
      expect(info.releasedAt, isNull);
      expect(info.releaseNotes, isEmpty);
      expect(info.downloadUrl, '');
    });

    test('字段类型错误（字符串数字 / 数字字符串）→ 默认值，不抛异常', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{
        'versionCode': '两',
        'versionName': 123,
        'minSupportedVersionCode': true,
      });
      expect(info.versionCode, 0);
      expect(info.versionName, '');
      expect(info.minSupportedVersionCode, 0);
    });

    test('releaseNotes 混入非字符串 → 只保留字符串项', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{
        'releaseNotes': <Object?>['修复 A', 123, null, '优化 B'],
      });
      expect(info.releaseNotes, <String>['修复 A', '优化 B']);
    });

    test('releaseNotes 类型错误（字符串）→ 空列表，不抛异常', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{
        'releaseNotes': '不是列表',
      });
      expect(info.releaseNotes, isEmpty);
    });

    test('releasedAt 是非法日期字符串 → null，不抛异常', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{
        'releasedAt': 'not-a-date',
      });
      expect(info.releasedAt, isNull);
    });

    test('releasedAt 类型错误（数字）→ null，不抛异常', () {
      final UpdateInfo info = UpdateInfo.fromJson(<String, dynamic>{
        'releasedAt': 123,
      });
      expect(info.releasedAt, isNull);
    });
  });
}
