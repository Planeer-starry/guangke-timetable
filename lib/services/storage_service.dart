import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timetable/models/timetable_data.dart';

/// 课表文件读写服务。
///
/// 目录必须从构造函数注入（便于单测改用临时目录，见 AGENTS.md 5.1）；
/// App 运行时用 [forApp] 便利工厂走 `path_provider`。
/// 禁止在本类内部直接调用 `getApplicationDocumentsDirectory()`。
class StorageService {
  StorageService({required Directory directory}) : _dir = directory;

  final Directory _dir;

  /// 课表文件名。
  static const String fileName = 'timetable.json';

  /// 导入快照文件名（与主文件同目录，恢复入口的数据源）。
  static const String snapshotFileName = 'imported.timetable.json';

  /// 便利工厂：取应用文档目录。仅供 App 运行时使用，测试请用构造函数注入。
  static Future<StorageService> forApp() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return StorageService(directory: dir);
  }

  File get _file => File('${_dir.path}${Platform.pathSeparator}$fileName');

  File get _snapshotFile =>
      File('${_dir.path}${Platform.pathSeparator}$snapshotFileName');

  /// 读取课表。
  ///
  /// 文件不存在或解析失败都**不抛异常**，返回空课表；
  /// 解析失败时把损坏文件重命名为 `timetable.json.corrupt.<毫秒时间戳>`，
  /// 不静默丢弃，用户可能还能救回来。
  Future<TimetableData> load() async {
    final File file = _file;
    if (!await file.exists()) {
      return TimetableData.empty();
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('课表文件顶层不是 JSON 对象');
      }
      return TimetableData.fromJson(decoded);
    } catch (error, stackTrace) {
      debugPrint('课表文件解析失败，已备份损坏文件：$error\n$stackTrace');
      await _backupCorruptFile(file);
      return TimetableData.empty();
    }
  }

  /// 把损坏的课表文件重命名保留；重命名失败也不影响返回空课表。
  Future<void> _backupCorruptFile(File file) async {
    try {
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      await file.rename('${file.path}.corrupt.$stamp');
    } catch (error) {
      debugPrint('损坏文件备份失败：$error');
    }
  }

  /// 保存课表（原子写，流程见 [_atomicWrite]）。
  Future<void> save(TimetableData data) async {
    await _atomicWrite(_file, _encode(data));
  }

  // ───────────────────── 导入快照（J4：恢复导入的原始课表） ─────────────────────

  /// 保存「最近一次导入」的快照（原子写，与主文件同一套流程）。
  Future<void> saveImportedSnapshot(TimetableData data) async {
    await _atomicWrite(_snapshotFile, _encode(data));
  }

  /// 读取导入快照：文件不存在 / 解析失败 → null，**绝不抛**。
  ///
  /// 与 [load] 不同，损坏的快照不备份改名——快照只是恢复点，
  /// 下次导入会直接覆盖，留备份没有意义。
  Future<TimetableData?> loadImportedSnapshot() async {
    final File file = _snapshotFile;
    if (!await file.exists()) {
      return null;
    }
    try {
      final String content = await file.readAsString();
      final Object? decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return TimetableData.fromJson(decoded);
    } catch (error) {
      debugPrint('导入快照解析失败：$error');
      return null;
    }
  }

  /// 是否存在导入快照（设置页恢复入口的显隐依据）。
  Future<bool> hasImportedSnapshot() async {
    return _snapshotFile.exists();
  }

  String _encode(TimetableData data) {
    return const JsonEncoder.withIndent('  ').convert(data.toJson());
  }

  /// 原子写：tmp → rename，主文件与快照共用。
  ///
  /// 流程：
  /// 1. 完整 JSON 先写**同目录**临时文件 `.tmp` 并 flush
  ///    （同目录保证 rename 不跨分区，这是原子性的前提）；
  /// 2. 目标已存在时先把它 rename 成 `.bak`
  ///    （Windows 上 rename 到已存在的目标可能失败）；
  /// 3. `tmp` rename 成目标；若失败则把 `.bak` 改回（回滚，旧数据不丢）再抛错；
  /// 4. 成功后删除 `.bak`。
  ///
  /// 任何时刻目标文件要么是旧的完整文件、要么是新的完整文件。
  Future<void> _atomicWrite(File file, String content) async {
    final File tmp = File('${file.path}.tmp');
    final File bak = File('${file.path}.bak');
    await tmp.writeAsString(content, flush: true);

    final bool hasOld = await file.exists();
    if (hasOld) {
      if (await bak.exists()) {
        await bak.delete();
      }
      await file.rename(bak.path);
    }
    try {
      await tmp.rename(file.path);
    } catch (error) {
      if (hasOld && await bak.exists()) {
        try {
          await bak.rename(file.path);
        } catch (rollbackError) {
          debugPrint('文件回滚失败：$rollbackError');
        }
      }
      rethrow;
    }
    if (hasOld && await bak.exists()) {
      await bak.delete();
    }
  }
}
