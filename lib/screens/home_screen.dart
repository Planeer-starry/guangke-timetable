import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/screens/import_flow.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/screens/settings_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/update_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_mask.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final ValueNotifier<TimetableData> _data;
  late final ValueNotifier<int> _displayWeek;
  late final ValueNotifier<UpdateInfo?> _updateInfo;
  bool _updateBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = ValueNotifier<TimetableData>(widget.initialData);
    _displayWeek = ValueNotifier<int>(_initialWeek(widget.initialData));
    _updateInfo = ValueNotifier<UpdateInfo?>(null);
    // 修正 A1：启动后（首帧后）静默检查一次更新，失败完全不提示
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateSilently());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _data.dispose();
    _displayWeek.dispose();
    _updateInfo.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App 从后台恢复（如早上打开）：立即重算并刷新小组件
      WidgetService.refreshAll(_data.value);
    }
  }

  /// 修正 A1：启动后静默检查更新，失败完全不提示、不影响使用。
  Future<void> _checkUpdateSilently() async {
    // 未配置更新地址（updateInfoUrl 为空）→ 整个更新功能关闭，
    // 不发起任何网络请求，App 完全离线
    if (!isUpdateEnabled) {
      return;
    }
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      final int current = int.tryParse(packageInfo.buildNumber) ?? 0;
      final UpdateInfo? info = await UpdateService.checkForUpdate(
        currentVersionCode: current,
        packageName: packageInfo.packageName,
      );
      if (info == null || !mounted) {
        return;
      }
      if (info.isForceUpdateFor(current)) {
        _showForceUpdateDialog(info);
        return;
      }
      setState(() => _updateInfo.value = info);
    } catch (error) {
      // 检查更新失败完全静默，绝不影响使用（修正 A1）
    }
  }

  /// 强制更新：不可关闭的对话框拦住（点外部、返回键都无法关闭）。
  void _showForceUpdateDialog(UpdateInfo info) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('需要更新'),
          content: Text('当前版本过旧，必须更新到 ${info.versionName} 才能继续使用。'),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openSettings();
              },
              child: const Text('立即更新'),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开设置页；返回时若学期参数变了，重算浏览周。
  Future<void> _openSettings() async {
    final TimetableData before = _data.value;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          data: _data,
          storage: widget.storage,
          settings: widget.settings,
          initialUpdate: _updateInfo.value,
        ),
      ),
    );
    final TimetableData after = _data.value;
    if (after.meta.week1Monday != before.meta.week1Monday ||
        after.meta.totalWeeks != before.meta.totalWeeks) {
      _displayWeek.value = _effectiveWeek(after);
    }
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
    WidgetService.refreshAll(updated);
  }

  // ───────────────────────── 导入流程 ─────────────────────────

  /// 打开导入流程（文件 / 剪贴板），与设置页共用（import_flow.dart）；
  /// 这里额外传 onDataChanged，用于导入后顺手设置学期时重算浏览周。
  Future<void> _startImport() {
    return startImportFlow(
      context,
      storage: widget.storage,
      data: _data,
      onDataChanged: (TimetableData updated) =>
          _displayWeek.value = _effectiveWeek(updated),
    );
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 深色下显式用 surface（M3 深灰）而非纯黑，给网格线留出对比空间
      backgroundColor: Theme.of(context).colorScheme.surface,
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
            tooltip: '设置',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          ValueListenableBuilder<UpdateInfo?>(
            valueListenable: _updateInfo,
            builder: (BuildContext context, UpdateInfo? info, _) =>
                _buildUpdateBanner(context, info),
          ),
          Expanded(
            child: ValueListenableBuilder<TimetableData>(
              valueListenable: _data,
              builder: (BuildContext context, TimetableData data, _) {
                if (!data.semesterConfigured) {
                  return _buildSetupGuide(context);
                }
                return _buildTimetable(context, data);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 首页顶部「发现新版本」提示条：可关闭；点「查看」进设置页下载。
  Widget _buildUpdateBanner(BuildContext context, UpdateInfo? info) {
    if (info == null || _updateBannerDismissed) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          Icon(
            Icons.system_update,
            size: 18,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '发现新版本 ${info.versionName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(onPressed: _openSettings, child: const Text('查看')),
          IconButton(
            tooltip: '关闭提示',
            icon: const Icon(Icons.close, size: 18),
            color: Theme.of(context).colorScheme.onSecondaryContainer,
            onPressed: () => setState(() => _updateBannerDismissed = true),
          ),
          const SizedBox(width: 4),
        ],
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
                      onCellTap: (List<CourseOccurrence> cell) =>
                          _openCell(context, cell, data.periods),
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 点击课程格：单课直接进详情；多课（教务导出的分班/选项课）先弹选择列表。
  Future<void> _openCell(
    BuildContext context,
    List<CourseOccurrence> cell,
    List<Period> periods,
  ) async {
    if (cell.length == 1) {
      showCourseDetailSheet(context, occurrence: cell.single, periods: periods);
      return;
    }
    final CourseOccurrence?
    picked = await showModalBottomSheet<CourseOccurrence>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '这一格有 ${cell.length} 门课（分班 / 选项课）',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
            ),
            for (final CourseOccurrence occurrence in cell)
              ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Color(occurrence.course.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(occurrence.course.name),
                subtitle: Text(
                  '${occurrence.location.isEmpty ? '地点未定' : occurrence.location}'
                  ' · ${formatWeekRanges(weeksFromWeekMask(occurrence.course.weekMask))}',
                ),
                onTap: () => Navigator.of(sheetContext).pop(occurrence),
              ),
          ],
        ),
      ),
    );
    // 跨 await 后使用 BuildContext 必须检查 context.mounted，
    // 不能用 State.mounted（lint: use_build_context_synchronously）
    if (picked != null && context.mounted) {
      showCourseDetailSheet(context, occurrence: picked, periods: periods);
    }
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
