import 'dart:convert';
import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/screens/import_preview_screen.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/timetable_importer.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 课表导入完整流程（首页与设置页共用）：
/// 选来源（JSON 文件 / 剪贴板 / 教务 Excel）→ 读内容 → 解析 → 预览 →
/// 确认后**全量替换**（教务 Excel 还会自动填写学期三件套）。
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
    // 与课程操作面板共用同一套外壳与零件（限宽 480 / 圆角 28 / 拖拽条 /
    // 头部卡片 / 动作行），保证「所有底部弹窗长得一样」。
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String? source = await showModalBottomSheet<String>(
      context: context,
      constraints: courseSheetConstraints,
      backgroundColor: colors.surfaceContainerLow,
      shape: courseSheetShape,
      clipBehavior: Clip.antiAlias,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SheetDragHandle(),
            SheetHeaderCard(
              color: colors.primary,
              title: '导入课表',
              lines: <String>['选择数据来源。导入后会替换当前课表'],
            ),
            const SizedBox(height: 8),
            SheetActionRow(
              icon: Icons.table_view,
              title: '从教务 Excel 导入',
              subtitle: '.xls / .xlsx · 自动识别学期、节次与周次',
              onTap: () => Navigator.of(sheetContext).pop('jwxt'),
            ),
            SheetActionRow(
              icon: Icons.folder_open,
              title: '从文件导入',
              subtitle: '.json · 简课表备份，或教务 / 爬虫生成的文件',
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
            SheetActionRow(
              icon: Icons.content_paste,
              title: '从剪贴板导入',
              subtitle: '粘贴 JSON 文本',
              onTap: () => Navigator.of(sheetContext).pop('clipboard'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) {
      return;
    }
    switch (source) {
      case 'jwxt':
        await _importJwxtExcel();
      case 'file':
        final String? content = await _readPickedFile();
        if (content != null && context.mounted) {
          await _parseAndPreviewJson(content);
        }
      case 'clipboard':
        final String? content = await _readClipboard();
        if (content != null && context.mounted) {
          await _parseAndPreviewJson(content);
        }
    }
  }

  // ───────────────────── 教务 Excel 导入 ─────────────────────

  /// 选 .xls/.xlsx → 读字节 → excel_plus 解码 → 纯函数解析 → 预览。
  Future<void> _importJwxtExcel() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['xls', 'xlsx'],
    );
    if (picked.isEmpty || !context.mounted) {
      return;
    }
    final PlatformFile file = picked.single;

    // file_picker 13.x 的 PlatformFile 是抽象类，**没有 bytes 字段**，
    // 统一用 readAsBytes() 读取（内部会处理 path / blob / content URI）。
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      _snack('读取文件失败：$error');
      return;
    }

    final JwxtImportResult result;
    try {
      final Excel excel = await Excel.decodeBytesAsync(bytes);
      if (excel.tables.isEmpty) {
        _snack('表格里没有任何工作表');
        return;
      }
      final Sheet sheet = excel.tables.values.first;
      // 转成纯字符串矩阵：解析逻辑在 jwxt_excel_importer 里单测，不碰 excel_plus
      final List<List<String?>> rows = sheet.rows
          .map(
            (List<dynamic> row) =>
                row.map((dynamic cell) => cell?.value?.toString()).toList(),
          )
          .toList();
      result = parseJwxtWorkbook(rows);
    } catch (error) {
      _snack('无法解析这个 Excel 文件：$error');
      return;
    }
    if (!result.isSuccessful) {
      // 空表/无法识别：SnackBar 装不下多行建议，改用 AlertDialog
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('这个表格格式暂时无法识别'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 保留解析器的具体原因（「未找到表头」/「未识别到课程」），
              // 用户报 Issue 时能直接说明，也便于区分「选错文件」和「格式不支持」
              if (result.error != null) ...<Widget>[
                Text(
                  result.error!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text('① 先导入后手动添加课程（AppBar「+」）'),
              const SizedBox(height: 8),
              const Text('② 把表格发到 GitHub Issue 附上学校名，我们适配'),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    final ImportConfirmation? confirmed = await Navigator.of(context)
        .push<ImportConfirmation>(
          MaterialPageRoute<ImportConfirmation>(
            builder: (_) => ImportPreviewScreen(
              courses: result.courses,
              skippedCount: result.skippedCount,
              jwxt: result,
              currentMeta: data.value.meta,
            ),
          ),
        );
    if (confirmed == null || confirmed.courses.isEmpty) {
      return;
    }
    await _applyImported(confirmed);
  }

  // ───────────────────── JSON 导入（原有路径） ─────────────────────

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

  Future<void> _parseAndPreviewJson(String content) async {
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
    // 类型提升只在当前作用域生效；下面 builder 闭包里要用它判断
    // 是不是 App 备份，所以先存成一个明确类型的局部变量。
    final Map<String, dynamic> root = decoded;
    final ImportResult result = parseImportedTimetable(root);
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
    final ImportConfirmation? confirmed = await Navigator.of(context)
        .push<ImportConfirmation>(
          MaterialPageRoute<ImportConfirmation>(
            builder: (_) => ImportPreviewScreen(
              courses: result.courses,
              skippedCount: result.skippedCount,
              currentMeta: data.value.meta,
              importedMeta: result.meta,
              importedPeriods: result.periods,
              importedOverrides: result.overrides,
              isFullBackup: root.containsKey('courses'),
            ),
          ),
        );
    if (confirmed == null || confirmed.courses.isEmpty) {
      return;
    }
    await _applyImported(confirmed);
  }

  // ───────────────────── 落盘 ─────────────────────

  /// 确认导入：**全量替换** courses/overrides（跨学期隔离，绝不与旧课合并）。
  ///
  /// - overrides 按 course.id 引用，而导入的课程 id 全新（c_xxx / jw_xxx），
  ///   旧 overrides 必然失效，必须同时清空；简课表备份除外——它带回
  ///   自己的 overrides（courseId 与课程一起恢复）；
  /// - 教务 Excel / JSON 携带的学期三件套，用户确认后连同 meta 一起写入
  ///   （week1Monday / totalWeeks / semesterName），免去手动设学期；
  /// - 作息**绝不缩水**：文件携带且校验通过的非空 periods 才写入，
  ///   否则沿用现有（[TimetableData.fromJson] 已保证现有 periods 非空）。
  Future<void> _applyImported(ImportConfirmation confirmed) async {
    final TimetableData current = data.value;
    final TimetableMeta meta =
        confirmed.week1Monday != null && confirmed.totalWeeks != null
        ? TimetableMeta(
            school: current.meta.school,
            semesterName: confirmed.semesterName ?? current.meta.semesterName,
            week1Monday: confirmed.week1Monday!,
            totalWeeks: confirmed.totalWeeks!,
          )
        : current.meta;
    final List<Period> periods = (confirmed.periods?.isNotEmpty ?? false)
        ? confirmed.periods!
        : current.periods;
    final TimetableData updated = TimetableData(
      schema: current.schema,
      meta: meta,
      periods: periods,
      courses: confirmed.courses,
      overrides: confirmed.overrides ?? const <CourseOverride>[],
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
    // 主数据落盘成功后存「导入快照」（J4 恢复入口的数据源）。
    // 快照失败不阻断导入主流程、也不弹错误提示——
    // 此时导入本身已成功，弹错会误导用户以为导入失败；
    // 下次导入会重新覆盖快照，损失只是本次会话没有恢复点。
    try {
      await storage.saveImportedSnapshot(updated);
    } catch (error) {
      debugPrint('导入快照保存失败：$error');
    }
    _emitUpdated(updated);
    if (!updated.semesterConfigured && context.mounted) {
      // 导入成功但学期仍未配置（JSON 路径且从未设置过）：
      // 明确提示并引导设置，避免用户误以为导入失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入成功，共 ${confirmed.courses.length} 门课。请先设置学期开始日才能查看课表',
          ),
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
    WidgetService.refreshAll(updated);
    onDataChanged?.call(updated);
  }

  void _snack(String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
