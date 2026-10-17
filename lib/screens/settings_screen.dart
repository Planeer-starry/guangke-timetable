import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/models/update_info.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/apk_installer.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/services/update_service.dart';
import 'package:timetable/services/widget_service.dart';

/// 设置页（基础版）：学期参数入口 + 关于 + 应用内更新。
///
/// 外观（主题切换）、课表管理（清空课表）等分组在后续任务再补，
/// 本页先保证「检查更新」完整可用。
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

/// 检查更新的状态机：idle → checking → upToDate / newVersion / error。
enum _UpdateStatus { idle, checking, upToDate, newVersion, error }

class _SettingsScreenState extends State<SettingsScreen> {
  _UpdateStatus _status = _UpdateStatus.idle;
  UpdateInfo? _updateInfo;

  String _appVersion = '';
  int _versionCode = 0;
  String _packageName = '';

  final ValueNotifier<double> _downloadProgress = ValueNotifier<double>(0);
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _updateInfo = widget.initialUpdate;
    _status = widget.initialUpdate == null
        ? _UpdateStatus.idle
        : _UpdateStatus.newVersion;
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _downloadProgress.dispose();
    super.dispose();
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
    WidgetService.refreshNextClass(updated);
  }

  /// 主动检查更新：绕过缓存重新拉 version.json，失败给出可见提示。
  Future<void> _checkUpdate() async {
    setState(() => _status = _UpdateStatus.checking);
    try {
      final UpdateInfo fetched = await UpdateService.fetchUpdateInfo(
        forceRefresh: true,
      );
      if (!mounted) {
        return;
      }
      final UpdateInfo? result = UpdateService.evaluateUpdate(
        fetched,
        _versionCode,
        _packageName,
      );
      setState(() {
        _updateInfo = result;
        _status = result == null
            ? _UpdateStatus.upToDate
            : _UpdateStatus.newVersion;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = _UpdateStatus.error);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('检查更新失败：$error')));
    }
  }

  /// 下载 APK（边下边校验 sha256）→ 拉起系统安装器。
  Future<void> _downloadAndInstall() async {
    final UpdateInfo? info = _updateInfo;
    if (info == null || _downloading) {
      return;
    }
    setState(() => _downloading = true);
    _downloadProgress.value = 0;
    try {
      final File file = await UpdateService.downloadApk(
        info,
        onProgress: (double progress) => _downloadProgress.value = progress,
      );
      final bool started = await ApkInstaller.installApk(file.path);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没能拉起安装器：请先允许本应用「安装未知应用」再重试')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
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
          _buildAboutSection(context),
          _buildUpdateSection(context),
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

  // ───────────────────────── 关于与更新 ─────────────────────────

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
      ],
    );
  }

  Widget _buildUpdateSection(BuildContext context) {
    final bool checking = _status == _UpdateStatus.checking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, '更新'),
        ListTile(
          leading: const Icon(Icons.system_update),
          title: const Text('检查更新'),
          subtitle: Text(_updateSubtitle()),
          trailing: checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          onTap: checking ? null : _checkUpdate,
        ),
        if (_status == _UpdateStatus.newVersion && _updateInfo != null)
          _NewVersionCard(
            info: _updateInfo!,
            progress: _downloadProgress,
            downloading: _downloading,
            onInstall: _downloadAndInstall,
          ),
      ],
    );
  }

  String _updateSubtitle() {
    switch (_status) {
      case _UpdateStatus.idle:
        return '点此检查是否有新版本';
      case _UpdateStatus.checking:
        return '正在检查…';
      case _UpdateStatus.upToDate:
        return '已是最新版本';
      case _UpdateStatus.newVersion:
        return '发现新版本 ${_updateInfo?.versionName ?? ''}';
      case _UpdateStatus.error:
        return '检查失败，点此重试';
    }
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

/// 新版本信息卡片：版本号、大小、更新说明、下载进度与安装按钮。
class _NewVersionCard extends StatelessWidget {
  const _NewVersionCard({
    required this.info,
    required this.progress,
    required this.downloading,
    required this.onInstall,
  });

  final UpdateInfo info;
  final ValueNotifier<double> progress;

  /// 是否正在下载；true 时显示进度条，false 显示「下载并安装」按钮。
  final bool downloading;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '新版本 ${info.versionName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (info.size > 0)
                  Text('${(info.size / 1024 / 1024).toStringAsFixed(1)} MB'),
              ],
            ),
            if (info.releaseNotes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              for (final String note in info.releaseNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· $note'),
                ),
            ],
            const SizedBox(height: 12),
            if (downloading)
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (BuildContext context, double value, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    LinearProgressIndicator(value: value <= 0 ? null : value),
                    const SizedBox(height: 4),
                    Text('正在下载… ${(value * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              )
            else
              FilledButton(onPressed: onInstall, child: const Text('下载并安装')),
          ],
        ),
      ),
    );
  }
}
