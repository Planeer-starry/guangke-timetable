import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/course.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/screens/import_flow.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/services/undo_stack.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/utils/breakpoints.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/widgets/app_card.dart';
import 'package:timetable/widgets/theme_pack_sheet.dart';
import 'package:timetable/widgets/update_section.dart';

/// 设置页：学期 / 外观 / 课表 / 关于 / 更新。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.data,
    required this.storage,
    required this.settings,
    required this.themeService,
    required this.undoStack,
    required this.initialUpdate,
  });

  final ValueNotifier<TimetableData> data;
  final StorageService storage;
  final SettingsService settings;

  /// 主题包服务（J6）：active 驱动界面种子色，coursePalette 驱动课程取色。
  final ThemeService themeService;

  /// 首页持有的撤销栈。
  ///
  /// 「恢复导入的原始课表」「清空课表」是整体替换语义，必须清空撤销栈——
  /// 否则用户回到首页点撤销会退回替换前的编辑状态，与其预期不符。
  final UndoStack undoStack;

  /// 首页静默检查已拿到的新版本；null 表示没查到或还没查。
  final UpdateInfo? initialUpdate;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  int _versionCode = 0;
  String _packageName = '';

  /// 是否存在导入快照（「恢复导入的原始课表」入口的显隐依据）。
  bool _hasImportedSnapshot = false;

  /// 主题模式的显示文案（存储值 → 中文）。
  static const Map<String, String> _themeModeLabels = <String, String>{
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
  };

  @override
  void initState() {
    super.initState();
    _lastThemePack = widget.themeService.active.value;
    widget.themeService.active.addListener(_onThemePackChanged);
    _loadPackageInfo();
    _checkImportedSnapshot();
  }

  @override
  void dispose() {
    widget.themeService.active.removeListener(_onThemePackChanged);
    super.dispose();
  }

  /// 上一次见到的主题包（判断课程调色板是否变化）。
  ThemePack _lastThemePack = ThemePack.fallback;

  /// 主题包变化（面板点选 / 导入 / 删除回退都会走到）：
  /// - 任何变化：同步小组件强调色并刷新小组件；
  /// - 课程调色板变化：按新调色板重取所有课程颜色（压撤销栈）。
  void _onThemePackChanged() {
    final ThemePack pack = widget.themeService.active.value;
    final bool paletteChanged = !_samePalette(
      _lastThemePack.coursePalette,
      pack.coursePalette,
    );
    _lastThemePack = pack;
    WidgetService.setAccent(pack);
    if (paletteChanged) {
      _reapplyCourseColors();
    } else {
      // 只换种子色（课程配色没变）也要让小组件高亮跟上
      WidgetService.refreshAll(widget.data.value);
    }
  }

  /// 从 .json 文件导入主题包；选中与重新取色由 [_onThemePackChanged]
  /// 对 active 的监听统一处理，这里只负责读文件与结果反馈。
  Future<void> _importThemePack() async {
    final List<PlatformFile> picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    if (picked.isEmpty || !mounted) {
      return;
    }
    // file_picker 13.x：PlatformFile 是抽象类没有 bytes 字段，
    // 统一 readAsBytes（内部处理 path / blob / content URI）
    final String text;
    try {
      text = utf8.decode(await picked.single.readAsBytes());
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读取文件失败：$error')));
      return;
    }
    final ImportOutcome outcome = await widget.themeService.importFromJson(
      text,
    );
    if (!mounted) {
      return;
    }
    // ok（可能有 warning）/ 失败（error），有信息就提示
    final String? message = outcome.ok ? outcome.warning : outcome.error;
    if (message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 课程调色板变化后的全量重取色（J6）：每门课按当前调色板重算
  /// colorValue，保存 + 更新内存 + 刷新小组件。
  ///
  /// ⚠️ **不压撤销栈**。撤销栈只存「课表数据快照」，不存当前调色板；
  /// 若把换配色前的数据压进去，用户撤销后课块会短暂恢复旧色，但
  /// `course_color` 的 activePalette 仍是新主题包的调色板 —— 下次启动
  /// `StorageService.load()` → `_migratePalette` 发现颜色不在当前调色板里，
  /// 又会按课名重取色，撤销被静默吞掉（实测确认过这个时序）。
  ///
  /// 主题包本身的撤销手段就是主题包选择器：切回原主题即恢复原配色。
  Future<void> _reapplyCourseColors() async {
    setActiveCoursePalette(widget.themeService.active.value.coursePalette);
    final TimetableData current = widget.data.value;
    final TimetableData updated = current.copyWith(
      courses: <Course>[
        for (final Course course in current.courses)
          course.copyWith(colorValue: colorValueFromName(course.name)),
      ],
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
    widget.data.value = updated;
    // ⚠️ 不能漏：小组件的课程色块颜色由这次刷新同步
    WidgetService.refreshAll(updated);
  }

  /// 两个可选调色板是否逐元素相同（含 null 情形）。
  static bool _samePalette(List<int>? a, List<int>? b) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkImportedSnapshot() async {
    final bool has = await widget.storage.hasImportedSnapshot();
    if (!mounted) {
      return;
    }
    setState(() => _hasImportedSnapshot = has);
  }

  Future<void> _loadPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _appVersion = info.version;
      _versionCode = int.tryParse(info.buildNumber) ?? 0;
      _packageName = info.packageName;
    });
  }

  /// 跳学期设置页；保存成功后写回 data 通知首页刷新。
  Future<void> _openSemesterSetup() async {
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) => SemesterSetupScreen(
              data: widget.data.value,
              storage: widget.storage,
            ),
          ),
        );
    if (updated == null) {
      return;
    }
    widget.data.value = updated;
    WidgetService.refreshAll(updated);
  }

  /// 外观：底部弹窗三选一（跟随系统 / 浅色 / 深色）。
  Future<void> _pickThemeMode(BuildContext context, String current) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final MapEntry<String, String> option
                in _themeModeLabels.entries)
              ListTile(
                title: Text(option.value),
                trailing: option.key == current
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) {
      return;
    }
    await widget.settings.setThemeMode(picked);
  }

  /// 恢复导入的原始课表：确认后用快照整体替换当前数据。
  ///
  /// 恢复本身是重置操作，**不进撤销栈**（栈在 HomeScreen，这里拿不到；
  /// 且语义上恢复 = 放弃所有手动修改，不该被「撤销」回去）。
  /// 快照文件保留——用户再改乱后仍可再次恢复。
  Future<void> _confirmRestoreImported() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('恢复导入的原始课表'),
        content: const Text('当前的所有手动修改（编辑 / 移动 / 停课 / 删除）都会丢失。'),
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
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final TimetableData? snapshot = await widget.storage.loadImportedSnapshot();
    if (snapshot == null) {
      // 快照在进入设置页后被动过/损坏：入口隐藏并提示
      if (mounted) {
        setState(() => _hasImportedSnapshot = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('快照不可用，无法恢复')));
      }
      return;
    }
    try {
      await widget.storage.save(snapshot);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('恢复失败：$error')));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    widget.data.value = snapshot;
    // 恢复 = 整体重置，撤销栈里的旧快照已无意义，必须清空，
    // 否则用户回首页点撤销会退回「恢复到这份快照之前」的编辑状态。
    widget.undoStack.clear();
    WidgetService.refreshAll(snapshot);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复到最近一次导入的状态')));
  }

  /// 清空课表：危险操作，二次确认后全量重置（含学期设置）。
  Future<void> _confirmClearTimetable() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('清空课表'),
        content: const Text('将删除本机保存的全部课程和调课记录，学期设置也会被重置。此操作不可恢复，确定清空吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final TimetableData cleared = TimetableData.empty();
    try {
      await widget.storage.save(cleared);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('清空失败：$error')));
      return;
    }
    widget.data.value = cleared;
    // 清空 = 整体重置，撤销栈必须清空（与恢复原始课表同理）。
    widget.undoStack.clear();
    WidgetService.refreshAll(cleared);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('课表已清空')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appPageBackground(Theme.of(context).colorScheme),
      appBar: AppBar(title: const Text('设置')),
      // expanded（平板）走双栏卡片；compact / medium 保持单列列表。
      // 断点只在这里读一次；两个分支复用同一批 _buildXxxContent，
      // 分组内容绝不复制两份
      body: windowSizeOf(context).isExpanded
          ? _buildExpandedBody(context)
          : _buildCompactBody(context),
    );
  }

  /// 手机 / 横屏：单列 ListView（与双栏改造前完全一致的结构）。
  Widget _buildCompactBody(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        _buildSemesterContent(context),
        const Divider(height: 24, indent: 16, endIndent: 16),
        _buildAppearanceContent(context),
        const Divider(height: 24, indent: 16, endIndent: 16),
        _buildTimetableContent(context),
        const Divider(height: 24, indent: 16, endIndent: 16),
        _buildAboutContent(context),
        // updateInfoUrl 为空（未配置托管地址）时整组隐藏，
        // 避免用户点了一个必然失败的按钮
        if (isUpdateEnabled) ...<Widget>[
          const Divider(height: 24, indent: 16, endIndent: 16),
          _buildUpdateContent(context),
        ],
      ],
    );
  }

  /// 平板：限宽 1100 双栏——左列学期+外观，右列课表+关于(+更新)。
  /// 容器（Card）在这里决定，内容与单列完全同源（_buildXxxContent）。
  Widget _buildExpandedBody(BuildContext context) {
    // 用 Align(topCenter) 而不是 Center：Center 也会把内容【垂直】居中，
    // 在 1200dp 高的平板上会让卡片整体下移、顶部空出一大块。
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  children: <Widget>[
                    _card(context, _buildSemesterContent(context)),
                    const SizedBox(height: 16),
                    _card(context, _buildAppearanceContent(context)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: <Widget>[
                    _card(context, _buildTimetableContent(context)),
                    const SizedBox(height: 16),
                    _card(context, _buildAboutContent(context)),
                    if (isUpdateEnabled) ...<Widget>[
                      const SizedBox(height: 16),
                      _card(context, _buildUpdateContent(context)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 双栏模式下的分组卡片容器。
  ///
  /// 用 surfaceContainerHigh + 1dp 描边：
  /// surfaceContainerLow 在深色模式下与背景几乎同色，只能靠圆角轮廓分辨，
  /// 加一档容器色和一圈 subtle 描边后深浅色都有清晰的卡片边界。
  Widget _card(BuildContext context, Widget child) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Card(
      elevation: colors.brightness == Brightness.light ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      color: appCardColor(colors),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  // ───────────────────────── 学期 ─────────────────────────

  /// 「学期」分组内容（容器由 compact/expanded 分支决定）。
  Widget _buildSemesterContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '学期'),
        ValueListenableBuilder<TimetableData>(
          valueListenable: widget.data,
          builder: (BuildContext context, TimetableData data, _) => ListTile(
            leading: const Icon(Icons.event),
            title: Text(
              data.meta.semesterName.isEmpty ? '未命名学期' : data.meta.semesterName,
            ),
            subtitle: Text(_semesterSubtitle(data.meta)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSemesterSetup,
          ),
        ),
      ],
    );
  }

  String _semesterSubtitle(TimetableMeta meta) {
    if (meta.week1Monday == TimetableData.unsetWeek1Monday) {
      return '尚未设置学期开始日，点此设置';
    }
    return '第一周周一：${_formatDate(meta.week1Monday)} · 共 ${meta.totalWeeks} 周';
  }

  // ───────────────────────── 外观 ─────────────────────────

  /// 「外观」分组内容。
  Widget _buildAppearanceContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '外观'),
        ValueListenableBuilder<String>(
          valueListenable: widget.settings.themeModeListenable,
          builder: (BuildContext context, String mode, _) => ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('主题'),
            subtitle: Text(_themeModeLabels[mode] ?? '跟随系统'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickThemeMode(context, mode),
          ),
        ),
        ValueListenableBuilder<ThemePack>(
          valueListenable: widget.themeService.active,
          builder: (BuildContext context, ThemePack pack, _) => ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题包'),
            subtitle: Text(
              pack.coursePalette != null ? '${pack.name} · 含课程配色' : pack.name,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ThemePackSheet.show(
              context,
              service: widget.themeService,
              onImport: _importThemePack,
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── 课表 ─────────────────────────

  /// 「课表」分组内容。
  Widget _buildTimetableContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '课表'),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('导入课表'),
          subtitle: const Text('支持教务 Excel / JSON 文件 / 剪贴板，将替换当前课表'),
          onTap: () => startImportFlow(
            context,
            storage: widget.storage,
            data: widget.data,
          ),
        ),
        // 仅存在导入快照时显示（initState 异步查一次）
        if (_hasImportedSnapshot)
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('恢复导入的原始课表'),
            subtitle: const Text('丢弃所有手动修改，回到最近一次导入的状态'),
            onTap: _confirmRestoreImported,
          ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('清空课表'),
          subtitle: const Text('删除本机保存的全部课程，不可恢复'),
          onTap: _confirmClearTimetable,
        ),
      ],
    );
  }

  // ───────────────────────── 关于 ─────────────────────────

  /// 「关于」分组内容。
  Widget _buildAboutContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '关于'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('简课表'),
          subtitle: _appVersion.isEmpty
              ? null
              : Text('$_appVersion（build $_versionCode）'),
        ),
        ListTile(
          leading: const Icon(Icons.code),
          title: const Text('包名'),
          subtitle: Text(
            _packageName.isEmpty ? 'com.planeer.timetable' : _packageName,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            '所有数据仅保存在本机，不上传任何信息',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  // ───────────────────────── 更新 ─────────────────────────

  /// 「更新」分组内容（仅 isUpdateEnabled 时由外层插入）。
  Widget _buildUpdateContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '更新'),
        UpdateSection(initialUpdate: widget.initialUpdate),
      ],
    );
  }

  // ───────────────────────── 小部件 ─────────────────────────

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
