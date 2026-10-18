import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
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
import 'package:timetable/services/undo_stack.dart';
import 'package:timetable/services/update_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/theme/week_grid_dimens.dart';
import 'package:timetable/utils/breakpoints.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';
import 'package:timetable/widgets/course_detail_sheet.dart';
import 'package:timetable/widgets/week_grid.dart';

/// 星期几中文名（下标 = dayWeek - 1），用于移动成功的提示文案。
const List<String> _dayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

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

  /// 撤销栈：编辑/删除/新增/移动前压快照，导入/清空后整体清掉。
  final UndoStack _undoStack = UndoStack();

  /// 正在移动的课（已应用当周 override 后的实际上课信息）。
  CourseOccurrence? _movingOccurrence;

  /// 移动发起时的周次（「仅本周」调整时写入该周的 override）。
  int? _movingWeek;

  /// 是否处于「移动课程」模式。
  bool get _isMoving => _movingOccurrence != null;

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

  // ───────────────────────── 长按菜单 / 移动模式 ─────────────────────────

  /// 长按课程格 → 操作菜单（编辑 / 移动到… / 删除）。
  /// 多课格（分班/选项课）先弹选择列表，与点击流程一致。
  Future<void> _openCellMenu(
    BuildContext context,
    List<CourseOccurrence> cell,
    int week,
  ) async {
    CourseOccurrence occurrence;
    if (cell.length == 1) {
      occurrence = cell.single;
    } else {
      final CourseOccurrence? picked = await _pickOccurrence(context, cell);
      if (picked == null || !context.mounted) {
        return;
      }
      occurrence = picked;
    }
    final String? action = await showModalBottomSheet<String>(
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
                  '「${occurrence.course.name}」',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('移动到…'),
              onTap: () => Navigator.of(sheetContext).pop('move'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    // sheet 已关，再执行动作（与 detail sheet 的约定一致）
    if (action == 'edit') {
      _editCourse(occurrence.course);
    } else if (action == 'move') {
      _enterMoveMode(occurrence, week);
    } else if (action == 'delete') {
      _confirmDeleteCourse(occurrence.course);
    }
  }

  /// 多课格（分班/选项课）的选择列表，点击与长按流程共用。
  Future<CourseOccurrence?> _pickOccurrence(
    BuildContext context,
    List<CourseOccurrence> cell,
  ) {
    return showModalBottomSheet<CourseOccurrence>(
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
  }

  /// 进入移动模式：记录被移动的课与发起周次。
  /// 此后 PageView / 网格滚动 / 课块点击全部禁用，只响应落点选择。
  void _enterMoveMode(CourseOccurrence occurrence, int week) {
    setState(() {
      _movingOccurrence = occurrence;
      _movingWeek = week;
    });
  }

  /// 退出移动模式（取消 / 点回原位 / 完成移动）。
  void _exitMoveMode() {
    setState(() {
      _movingOccurrence = null;
      _movingWeek = null;
    });
  }

  /// 移动模式中点了目标时段（day=星期几，section=点击的节次）。
  ///
  /// 节数保持不变：以点击节次为起点，终点超出总节数时整体上移；
  /// 点回原位置视为放弃，直接退出。确认后二选一：
  /// 所有周（改课程本身）/ 仅本周（写 override）。
  Future<void> _onMoveTargetPicked(int day, int section) async {
    final CourseOccurrence? occurrence = _movingOccurrence;
    final int? week = _movingWeek;
    if (occurrence == null || week == null) {
      return;
    }
    final int totalPeriods = _data.value.periods.length;
    final int span = occurrence.sectionEnd - occurrence.sectionStart + 1;
    final int newEnd = (section + span - 1).clamp(1, totalPeriods).toInt();
    final int newStart = newEnd - span + 1;
    if (day == occurrence.dayWeek && newStart == occurrence.sectionStart) {
      _exitMoveMode();
      return;
    }
    // 0 = 应用到所有周（默认，永久修改课表）；1 = 仅本周（临时调整）
    int choice = 0;
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext dialogContext, StateSetter setDialogState) =>
            AlertDialog(
              title: const Text('移动课程'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 用 ListTile + Icons.check 而非 RadioListTile：
                  // Flutter 3.32+ 已废弃 RadioListTile 的 groupValue/onChanged
                  // （要改用 RadioGroup 祖先），项目里统一用这个写法避免告警。
                  ListTile(
                    leading: Icon(
                      choice == 0
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: const Text('应用到所有周（永久修改课表）'),
                    onTap: () => setDialogState(() => choice = 0),
                  ),
                  ListTile(
                    leading: Icon(
                      choice == 1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text('仅第 $week 周（临时调整）'),
                    onTap: () => setDialogState(() => choice = 1),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(choice),
                  child: const Text('确定'),
                ),
              ],
            ),
      ),
    );
    if (result == null) {
      // 取消对话框：保持移动模式，可重新选目标或点「取消」退出
      return;
    }
    final TimetableData updated;
    if (result == 0) {
      updated = CourseEditor.upsertCourse(
        _data.value,
        occurrence.course.copyWith(
          dayWeek: day,
          sectionStart: newStart,
          sectionEnd: newEnd,
        ),
      );
    } else {
      updated = CourseEditor.setOverride(
        _data.value,
        CourseOverride(
          courseId: occurrence.course.id,
          week: week,
          dayWeek: day,
          sectionStart: newStart,
          sectionEnd: newEnd,
          location: occurrence.location,
        ),
      );
    }
    _exitMoveMode();
    final bool ok = await _applyCourseUpdate(updated);
    if (!ok || !mounted) {
      return;
    }
    final String sectionText = newStart == newEnd
        ? '第 $newStart 节'
        : '第 $newStart~$newEnd 节';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '已移动到 周${_dayNames[day - 1]} $sectionText'
          '${result == 0 ? '' : '（仅第 $week 周）'}',
        ),
        action: SnackBarAction(label: '撤销', onPressed: _undo),
      ),
    );
  }

  /// 撤销最近一次编辑/删除/新增/移动。
  Future<void> _undo() async {
    final TimetableData? before = _undoStack.pop();
    if (before == null) {
      return;
    }
    try {
      await widget.storage.save(before);
    } catch (error) {
      // 保存失败：快照塞回去，不丢失这次撤销机会
      _undoStack.push(before);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('撤销失败：$error')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _data.value = before;
    });
    await WidgetService.refreshAll(before);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已撤销')));
    }
  }

  /// 编辑/删除/新增/移动统一落盘：压撤销栈 → 保存 → 更新内存 → 刷小组件。
  /// 四个入口共用；返回是否成功（移动流程据此决定要不要弹提示）。
  Future<bool> _applyCourseUpdate(TimetableData? updated) async {
    if (updated == null) {
      return false;
    }
    // 修改前快照压入撤销栈
    _undoStack.push(_data.value);
    try {
      await widget.storage.save(updated);
    } catch (error) {
      // 保存失败：数据没变，把刚压的快照弹掉，撤销按钮不该亮
      _undoStack.pop();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return false;
    }
    if (!mounted) {
      return false;
    }
    // setState 而非直接赋值：AppBar 撤销按钮的显隐依赖 canUndo，
    // 不在任何 ValueListenableBuilder 里，需要整页重建
    setState(() {
      _data.value = updated;
    });
    await WidgetService.refreshAll(updated);
    return true;
  }

  // ───────────────────────── 导入流程 ─────────────────────────

  /// 打开导入流程（文件 / 剪贴板），与设置页共用（import_flow.dart）；
  /// 这里额外传 onDataChanged，用于导入后顺手设置学期时重算浏览周。
  Future<void> _startImport() {
    return startImportFlow(
      context,
      storage: widget.storage,
      data: _data,
      onDataChanged: (TimetableData updated) {
        // 导入是整体替换：撤销栈清空，撤销不跨导入生效
        _undoStack.clear();
        setState(() {});
        _setDisplayWeek(
          _effectiveWeek(updated),
          updated.meta.totalWeeks,
          animate: false,
        );
      },
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
        // 移动模式中只留「取消移动」：导入/设置/+ 会改数据，
        // 让移动中的目标信息失效；平时显示撤销（栈空时整个不渲染）
        actions: _isMoving
            ? <Widget>[
                TextButton(onPressed: _exitMoveMode, child: const Text('取消移动')),
              ]
            : <Widget>[
                if (_undoStack.canUndo)
                  IconButton(
                    tooltip: '撤销',
                    iconSize: windowSize.isExpanded ? 28 : 24,
                    icon: const Icon(Icons.undo),
                    onPressed: _undo,
                  ),
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
        if (_isMoving) _buildMovingBanner(context),
        const Divider(height: 1),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: data.meta.totalWeeks,
            // iOS 式回弹：跟手 + 惯性 + 第 1 周 / 最后一周边缘回弹；
            // 移动模式禁翻页（防止发起周与目标周不一致）
            physics: _isMoving
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(parent: PageScrollPhysics()),
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
                onCellLongPress: (List<CourseOccurrence> cell) =>
                    _openCellMenu(context, cell, week),
                isMoving: _isMoving,
                movingCourseId: _movingOccurrence?.course.id,
                onMoveTargetPicked: _onMoveTargetPicked,
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
    final CourseOccurrence? picked = await _pickOccurrence(context, cell);
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

  /// 移动模式提示条：告知正在移动哪门课 + 取消入口。
  Widget _buildMovingBanner(BuildContext context) {
    final CourseOccurrence? occurrence = _movingOccurrence;
    if (occurrence == null) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          Icon(Icons.open_with, size: 18, color: colors.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '正在移动「${occurrence.course.name}」· 点目标时段',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onPrimaryContainer),
            ),
          ),
          TextButton(onPressed: _exitMoveMode, child: const Text('取消')),
          const SizedBox(width: 4),
        ],
      ),
    );
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
