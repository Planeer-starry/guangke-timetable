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
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/utils/timetable_importer.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_math.dart';
import 'package:timetable/widgets/course_detail_sheet.dart';
import 'package:timetable/widgets/week_grid.dart';

/// 周课表主页面。
///
/// 业务逻辑不写在 build 里：取某周课程用 timetable_query.coursesForWeek，
/// 算当前周次用 week_math.weekOfDate，导入解析用 timetable_importer。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialData,
    required this.storage,
    required this.settings,
  });

  final TimetableData initialData;
  final StorageService storage;
  final SettingsService settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ValueNotifier<TimetableData> _data;
  late final ValueNotifier<int> _displayWeek;

  @override
  void initState() {
    super.initState();
    _data = ValueNotifier<TimetableData>(widget.initialData);
    _displayWeek = ValueNotifier<int>(_initialWeek(widget.initialData));
  }

  @override
  void dispose() {
    _data.dispose();
    _displayWeek.dispose();
    super.dispose();
  }

  /// 当前周次：优先用户固定（weekOverride），否则由日历计算。
  int _effectiveWeek(TimetableData data) {
    final int? override = widget.settings.weekOverride;
    if (override != null) {
      return override;
    }
    return weekOfDate(
      DateTime.now(),
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
  }

  int _initialWeek(TimetableData data) {
    if (!data.semesterConfigured) {
      return 1;
    }
    return _effectiveWeek(data);
  }

  /// 翻页：只改内存里的浏览位置，**不写 weekOverride**。
  void _goToWeek(int week, int totalWeeks) {
    final int clamped;
    if (week < 1) {
      clamped = 1;
    } else if (week > totalWeeks) {
      clamped = totalWeeks;
    } else {
      clamped = week;
    }
    _displayWeek.value = clamped;
  }

  /// 回到本周：**清除**周次覆盖（恢复跟随日历），再把内存设为本周。
  Future<void> _backToCurrentWeek(TimetableData data) async {
    await widget.settings.setWeekOverride(null);
    _displayWeek.value = weekOfDate(
      DateTime.now(),
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
  }

  /// 打开学期设置页；保存成功会返回新的 TimetableData。
  Future<void> _openSemesterSetup() async {
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) =>
                SemesterSetupScreen(data: _data.value, storage: widget.storage),
          ),
        );
    if (updated == null) {
      return;
    }
    _data.value = updated;
    _displayWeek.value = _effectiveWeek(updated);
  }

  // ───────────────────────── 导入流程 ─────────────────────────

  /// 打开导入入口（文件 / 剪贴板）→ 解析 → 预览 → 确认应用。
  Future<void> _startImport() async {
    final String? source = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('从文件导入（.json）'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('从剪贴板导入'),
              onTap: () => Navigator.of(context).pop('clipboard'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) {
      return;
    }
    final String? content = source == 'file'
        ? await _readPickedFile()
        : await _readClipboard();
    if (content == null || !mounted) {
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
      if (!mounted) {
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
      if (!mounted) {
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('不是有效的 JSON：$error')));
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('JSON 顶层必须是对象')));
      return;
    }
    final ImportResult result = parseImportedTimetable(decoded);
    if (!result.isSuccessful) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? '未识别到任何课程，请检查文件内容')),
      );
      return;
    }
    if (!mounted) {
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
    final TimetableData current = _data.value;
    final TimetableData updated = TimetableData(
      schema: current.schema,
      meta: current.meta,
      periods: Period.defaults,
      courses: courses,
      overrides: const <CourseOverride>[],
    );
    try {
      await widget.storage.save(updated);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return;
    }
    _data.value = updated;
    if (!current.semesterConfigured && mounted) {
      // 导入成功但学期未配置：明确提示并引导设置，避免用户误以为导入失败
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入成功，共 ${courses.length} 门课。请先设置学期开始日才能查看课表'),
          action: SnackBarAction(label: '去设置', onPressed: _openSemesterSetup),
        ),
      );
    }
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<TimetableData>(
          valueListenable: _data,
          builder: (BuildContext context, TimetableData data, _) {
            return Text(
              data.meta.semesterName.isEmpty ? '广科课表' : data.meta.semesterName,
            );
          },
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '导入课表',
            icon: const Icon(Icons.upload_file),
            onPressed: _startImport,
          ),
          IconButton(
            tooltip: '设置学期',
            icon: const Icon(Icons.settings),
            onPressed: _openSemesterSetup,
          ),
        ],
      ),
      body: ValueListenableBuilder<TimetableData>(
        valueListenable: _data,
        builder: (BuildContext context, TimetableData data, _) {
          if (!data.semesterConfigured) {
            return _buildSetupGuide(context);
          }
          return _buildTimetable(context, data);
        },
      ),
    );
  }

  /// 学期未设置时的引导（首次启动必经）。
  Widget _buildSetupGuide(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.event, size: 64),
            const SizedBox(height: 16),
            const Text('还没有设置学期开始日，点这里设置第一周周一'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _openSemesterSetup,
              child: const Text('设置第一周周一'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetable(BuildContext context, TimetableData data) {
    return ValueListenableBuilder<int>(
      valueListenable: _displayWeek,
      builder: (BuildContext context, int week, _) {
        final List<CourseOccurrence> occurrences = coursesForWeek(data, week);
        final DateTime monday = mondayOfWeek(data.meta.week1Monday, week);
        final bool isCurrentWeek = week == _effectiveWeek(data);
        return Column(
          children: <Widget>[
            _buildWeekBar(context, week, data),
            const Divider(height: 1),
            Expanded(
              child: occurrences.isEmpty
                  ? _buildEmptyWeek(context)
                  : WeekGrid(
                      periods: data.periods,
                      occurrences: occurrences,
                      weekMonday: monday,
                      isCurrentWeek: isCurrentWeek,
                      onCourseTap: (CourseOccurrence occurrence) =>
                          showCourseDetailSheet(
                            context,
                            occurrence: occurrence,
                            periods: data.periods,
                          ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeekBar(BuildContext context, int week, TimetableData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一周',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goToWeek(week - 1, data.meta.totalWeeks),
          ),
          Expanded(child: Center(child: Text('第 $week 周'))),
          IconButton(
            tooltip: '下一周',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goToWeek(week + 1, data.meta.totalWeeks),
          ),
          TextButton(
            onPressed: () => _backToCurrentWeek(data),
            child: const Text('回到本周'),
          ),
        ],
      ),
    );
  }

  /// 该周没有课程时的空状态。
  Widget _buildEmptyWeek(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.event_busy, size: 64),
          const SizedBox(height: 16),
          const Text('还没有课表'),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _startImport,
            child: const Text('导入课表'),
          ),
        ],
      ),
    );
  }
}
