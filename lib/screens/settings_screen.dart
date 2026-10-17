import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/screens/import_flow.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/widget_service.dart';
import 'package:timetable/widgets/update_section.dart';

/// 设置页：学期 / 外观 / 课表 / 关于 / 更新。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.data,
    required this.storage,
    required this.settings,
    required this.initialUpdate,
  });

  final ValueNotifier<TimetableData> data;
  final StorageService storage;
  final SettingsService settings;

  /// 首页静默检查已拿到的新版本；null 表示没查到或还没查。
  final UpdateInfo? initialUpdate;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _appVersion = '';
  int _versionCode = 0;
  String _packageName = '';

  /// 主题模式的显示文案（存储值 → 中文）。
  static const Map<String, String> _themeModeLabels = <String, String>{
    'system': '跟随系统',
    'light': '浅色',
    'dark': '深色',
  };

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
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
    WidgetService.refreshAll(cleared);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('课表已清空')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _buildSemesterSection(context),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _buildAppearanceSection(context),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _buildTimetableSection(context),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _buildAboutSection(context),
          // updateInfoUrl 为空（未配置托管地址）时整组隐藏，
          // 避免用户点了一个必然失败的按钮
          if (isUpdateEnabled) ...<Widget>[
            _sectionTitle(context, '更新'),
            UpdateSection(initialUpdate: widget.initialUpdate),
          ],
        ],
      ),
    );
  }

  // ───────────────────────── 学期 ─────────────────────────

  Widget _buildSemesterSection(BuildContext context) {
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

  Widget _buildAppearanceSection(BuildContext context) {
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
      ],
    );
  }

  // ───────────────────────── 课表 ─────────────────────────

  Widget _buildTimetableSection(BuildContext context) {
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

  Widget _buildAboutSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '关于'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('广科课表'),
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
