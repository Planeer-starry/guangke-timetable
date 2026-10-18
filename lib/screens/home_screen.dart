import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/screens/course_edit_screen.dart';
import 'package:timetable/screens/import_flow.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/screens/settings_screen.dart';
import 'package:timetable/services/course_editor.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/update_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/theme/week_grid_dimens.dart';
import 'package:timetable/utils/breakpoints.dart';
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
  late final PageController _pageController;
  late final ValueNotifier<UpdateInfo?> _updateInfo;
  bool _updateBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = ValueNotifier<TimetableData>(widget.initialData);
    _displayWeek = ValueNotifier<int>(_initialWeek(widget.initialData));
    // PageView 页码 = 周次 - 1，初始对齐当前浏览周
    _pageController = PageController(initialPage: _displayWeek.value - 1);
    _updateInfo = ValueNotifier<UpdateInfo?>(null);
    // 修正 A1：启动后（首帧后）静默检查一次更新，失败完全不提示
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateSilently());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _data.dispose();
    _displayWeek.dispose();
    _pageController.dispose();
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
      // 学期参数变了：直接跳到新位置，不做滑动动画
      _setDisplayWeek(
        _effectiveWeek(after),
        after.meta.totalWeeks,
        animate: false,
      );
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

  /// 设置当前浏览周次并同步 PageView 位置（统一入口：
  /// _displayWeek 与 PageController 必须一起动，分开改会失步）。
  ///
  /// [animate] 为 true 时带滑动动画（按钮 / 回到本周）；
  /// false 直接跳（导入课表、改学期等数据变化场景，
  /// 否则会看到中间所有周快速滑过的动画）。
  void _setDisplayWeek(int week, int totalWeeks, {bool animate = true}) {
    // num.clamp 返回 num，必须 toInt 才能赋给 int
    final int clamped = week.clamp(1, totalWeeks).toInt();
    if (_displayWeek.value == clamped) {
      return;
    }
    _displayWeek.value = clamped;
    if (!_pageController.hasClients) {
      return;
    }
    if (animate) {
      // animateToPage 过程中会触发 onPageChanged；
      // 它只写 _displayWeek、不碰 controller（见 _buildTimetable），无死循环
      _pageController.animateToPage(
        clamped - 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(clamped - 1);
    }
  }

  /// 翻页：只改内存里的浏览位置，**不写 weekOverride**。
  void _goToWeek(int week, int totalWeeks) {
    _setDisplayWeek(week, totalWeeks);
  }

  /// 回到本周：**清除**周次覆盖（恢复跟随日历），再把内存设为本周。
  Future<void> _backToCurrentWeek(TimetableData data) async {
    await widget.settings.setWeekOverride(null);
    final int w = weekOfDate(
      DateTime.now(),
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
    _setDisplayWeek(w, data.meta.totalWeeks);
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
    _setDisplayWeek(
      _effectiveWeek(updated),
      updated.meta.totalWeeks,
      animate: false,
    );
    WidgetService.refreshAll(updated);
  }

  // ───────────────────────── 课程编辑 ─────────────────────────

  /// 新增课程：默认选当前浏览周；返回数据由 [_applyCourseUpdate] 落盘。
  Future<void> _addCourse() async {
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) => CourseEditScreen(
              data: _data.value,
              course: null,
              defaultWeek: _displayWeek.value,
            ),
          ),
        );
    await _applyCourseUpdate(updated);
  }

  /// 编辑课程：id 与颜色不变，其余字段由编辑页返回。
  Future<void> _editCourse(Course course) async {
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) => CourseEditScreen(data: _data.value, course: course),
          ),
        );
    await _applyCourseUpdate(updated);
  }

  /// 删除课程：二次确认 → 删课（连带 overrides）→ 落盘。
  Future<void> _confirmDeleteCourse(Course course) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除课程'),
        content: Text('确定删除「${course.name}」吗？该课程的所有调课记录也会一并删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    await _applyCourseUpdate(CourseEditor.deleteCourse(_data.value, course.id));
  }

  /// 编辑/删除统一落盘：保存 → 更新内存 → 刷小组件。
  /// 三个入口共用，避免同样的三行在 _add/_edit/_delete 里复制三遍。
  Future<void> _applyCourseUpdate(TimetableData? updated) async {
    if (updated == null) {
      return;
    }
    try {
      await widget.storage.save(updated);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _data.value = updated;
    await WidgetService.refreshAll(updated);
  }

  // ───────────────────────── 导入流程 ─────────────────────────

  /// 打开导入流程（文件 / 剪贴板），与设置页共用（import_flow.dart）；
  /// 这里额外传 onDataChanged，用于导入后顺手设置学期时重算浏览周。
  Future<void> _startImport() {
    return startImportFlow(
      context,
      storage: widget.storage,
      data: _data,
      onDataChanged: (TimetableData updated) => _setDisplayWeek(
        _effectiveWeek(updated),
        updated.meta.totalWeeks,
        animate: false,
      ),
    );
  }

  // ───────────────────────── 界面 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    // 断点在页面顶层读一次往下传（AppBar 部分）
    final WindowSize windowSize = windowSizeOf(context);
    return Scaffold(
      // 深色下显式用 surface（M3 深灰）而非纯黑，给网格线留出对比空间
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: ValueListenableBuilder<TimetableData>(
          valueListenable: _data,
          builder: (BuildContext context, TimetableData data, _) {
            return Text(
              data.meta.semesterName.isEmpty ? '广科课表' : data.meta.semesterName,
              // expanded 放大加粗；compact/medium 保持默认（titleLarge）
              style: windowSize.isExpanded
                  ? const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)
                  : null,
            );
          },
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '新增课程',
            iconSize: windowSize.isExpanded ? 28 : 24,
            icon: const Icon(Icons.add),
            onPressed: _addCourse,
          ),
          IconButton(
            tooltip: '导入课表',
            iconSize: windowSize.isExpanded ? 28 : 24,
            icon: const Icon(Icons.upload_file),
            onPressed: _startImport,
          ),
          IconButton(
            tooltip: '设置',
            iconSize: windowSize.isExpanded ? 28 : 24,
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
    // 断点在页面顶层读一次往下传，子 widget 不读 MediaQuery。
    // 窗口尺寸变化（平板旋转）会触发重建，这里自动重算
    final WindowSize windowSize = windowSizeOf(context);
    final WeekGridDimens dimens = WeekGridDimens.of(windowSize);
    // ⚠️ ValueListenableBuilder 只包【周条】：如果包住整个 Column，
    // 每次 _displayWeek 变化都会重建 PageView，滑动中途会被打断。
    return Column(
      children: <Widget>[
        ValueListenableBuilder<int>(
          valueListenable: _displayWeek,
          builder: (BuildContext context, int week, _) =>
              _buildWeekBar(context, week, data, windowSize),
        ),
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: data.meta.totalWeeks,
            // iOS 式回弹：跟手 + 惯性 + 第 1 周 / 最后一周边缘回弹
            physics: const BouncingScrollPhysics(parent: PageScrollPhysics()),
            onPageChanged: (int index) {
              // 滑动只写值，绝不再动 controller——
              // 否则与 _setDisplayWeek 的 animateToPage 互相触发死循环
              _displayWeek.value = index + 1;
            },
            itemBuilder: (BuildContext context, int index) {
              final int week = index + 1;
              final List<CourseOccurrence> occurrences = coursesForWeek(
                data,
                week,
              );
              if (occurrences.isEmpty) {
                return _buildEmptyWeek(context);
              }
              return WeekGrid(
                periods: data.periods,
                occurrences: occurrences,
                weekMonday: mondayOfWeek(data.meta.week1Monday, week),
                isCurrentWeek: week == _effectiveWeek(data),
                onCellTap: (List<CourseOccurrence> cell) =>
                    _openCell(context, cell, data.periods),
                dimens: dimens,
                windowSize: windowSize,
              );
            },
          ),
        ),
      ],
    );
  }

  /// 点击课程格：单课直接进详情；多课（教务导出的分班/选项课）先弹选择列表。
  Future<void> _openCell(
    BuildContext context,
    List<CourseOccurrence> cell,
    List<Period> periods,
  ) async {
    if (cell.length == 1) {
      final CourseOccurrence occurrence = cell.single;
      showCourseDetailSheet(
        context,
        occurrence: occurrence,
        periods: periods,
        onEdit: () => _editCourse(occurrence.course),
        onDelete: () => _confirmDeleteCourse(occurrence.course),
      );
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
      showCourseDetailSheet(
        context,
        occurrence: picked,
        periods: periods,
        onEdit: () => _editCourse(picked.course),
        onDelete: () => _confirmDeleteCourse(picked.course),
      );
    }
  }

  Widget _buildWeekBar(
    BuildContext context,
    int week,
    TimetableData data,
    WindowSize windowSize,
  ) {
    final bool isCurrentWeek = week == _effectiveWeek(data);
    final double chevronSize = switch (windowSize) {
      WindowSize.compact => 24.0,
      WindowSize.medium => 28.0,
      WindowSize.expanded => 32.0,
    };
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: windowSize.isExpanded ? 8 : 4,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一周',
            iconSize: chevronSize,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goToWeek(week - 1, data.meta.totalWeeks),
          ),
          Expanded(
            child: Center(
              child: Text(
                '第 $week 周',
                style: TextStyle(
                  fontSize: switch (windowSize) {
                    WindowSize.compact => 15.0,
                    WindowSize.medium => 17.0,
                    WindowSize.expanded => 20.0,
                  },
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            iconSize: chevronSize,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goToWeek(week + 1, data.meta.totalWeeks),
          ),
          // 只在不在本周时显示。用条件插入而非 Visibility/Opacity：
          // 隐藏时 Row 空间自然收拢，右侧不会空出一块。
          // expanded 用带图标的按钮，宽屏上更醒目也更容易点到
          if (!isCurrentWeek)
            if (windowSize.isExpanded)
              TextButton.icon(
                onPressed: () => _backToCurrentWeek(data),
                icon: const Icon(Icons.today),
                label: const Text('回到本周'),
              )
            else
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
