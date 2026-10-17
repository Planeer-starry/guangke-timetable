import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/import_preview_screen.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/timetable_importer.dart';

/// 课表导入完整流程（首页与设置页共用）：
/// 选来源（文件 / 剪贴板）→ 读内容 → 解析 → 预览 → 确认后**全量替换**。
///
/// [onDataChanged] 在每次课表数据落盘并更新 [data] 后回调
/// （含导入后顺手设置学期的场景），首页用它重算浏览周次。
Future<void> startImportFlow(
  BuildContext context, {
  required StorageService storage,
  required ValueNotifier<TimetableData> data,
  void Function(TimetableData updated)? onDataChanged,
}) {
  return _ImportFlow(
    context: context,
    storage: storage,
    data: data,
    onDataChanged: onDataChanged,
  ).run();
}

class _ImportFlow {
  _ImportFlow({
    required this.context,
    required this.storage,
    required this.data,
    this.onDataChanged,
  });

  final BuildContext context;
  final StorageService storage;
  final ValueNotifier<TimetableData> data;
  final void Function(TimetableData updated)? onDataChanged;

  Future<void> run() async {
    final String? source = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('从文件导入（.json）'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('从剪贴板导入'),
              onTap: () => Navigator.of(sheetContext).pop('clipboard'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) {
      return;
    }
    final String? content = source == 'file'
        ? await _readPickedFile()
        : await _readClipboard();
    if (content == null || !context.mounted) {
      return;
    }
    await _parseAndPreview(content);
  }

  Future<String?> _readPickedFile() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    final String? path = picked.isEmpty ? null : picked.single.path;
    if (path == null) {
      return null;
    }
    try {
      return await File(path).readAsString();
    } catch (error) {
      if (!context.mounted) {
        return null;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读取文件失败：$error')));
      return null;
    }
  }

  Future<String?> _readClipboard() async {
    final ClipboardData? clipboard = await Clipboard.getData('text/plain');
    final String? text = clipboard?.text;
    if (text == null || text.trim().isEmpty) {
      if (!context.mounted) {
        return null;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('剪贴板里没有内容')));
      return null;
    }
    return text;
  }

  Future<void> _parseAndPreview(String content) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('不是有效的 JSON：$error')));
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('JSON 顶层必须是对象')));
      return;
    }
    final ImportResult result = parseImportedTimetable(decoded);
    if (!result.isSuccessful) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '未识别到任何课程，请检查文件内容')),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final List<Course>? confirmed = await Navigator.of(context)
        .push<List<Course>>(
          MaterialPageRoute<List<Course>>(
            builder: (_) => ImportPreviewScreen(result: result),
          ),
        );
    if (confirmed == null || confirmed.isEmpty) {
      return;
    }
    await _applyImported(confirmed);
  }

  /// 确认导入：**全量替换** courses/overrides（跨学期隔离，绝不与旧课合并）。
  Future<void> _applyImported(List<Course> courses) async {
    final TimetableData current = data.value;
    final TimetableData updated = TimetableData(
      schema: current.schema,
      meta: current.meta,
      periods: Period.defaults,
      courses: courses,
      overrides: const <CourseOverride>[],
    );
    try {
      await storage.save(updated);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return;
    }
    _emitUpdated(updated);
    if (!current.semesterConfigured && context.mounted) {
      // 导入成功但学期未配置：明确提示并引导设置，避免用户误以为导入失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入成功，共 ${courses.length} 门课。请先设置学期开始日才能查看课表'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: _openSemesterSetupAfterImport,
          ),
        ),
      );
    }
  }

  /// 导入后学期未配置时，从提示条直接跳学期设置页。
  Future<void> _openSemesterSetupAfterImport() async {
    if (!context.mounted) {
      return;
    }
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) =>
                SemesterSetupScreen(data: data.value, storage: storage),
          ),
        );
    if (updated == null) {
      return;
    }
    _emitUpdated(updated);
  }

  /// 数据落盘后的统一出口：更新 notifier、刷新小组件、通知调用方。
  void _emitUpdated(TimetableData updated) {
    data.value = updated;
    WidgetService.refreshNextClass(updated);
    onDataChanged?.call(updated);
  }
}
