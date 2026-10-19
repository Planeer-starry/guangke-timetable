import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/widgets/palette_pack_sheet.dart';

/// 主题包 / 课程配色包管理页（J8）：顶部两个 tab 的列表，
/// 每行支持重命名 / 复制 JSON / 删除（内置包只读，仅可复制）。
class PackManagerScreen extends StatefulWidget {
  const PackManagerScreen({
    super.key,
    required this.themeService,
    required this.paletteService,
  });

  final ThemeService themeService;

  final PaletteService paletteService;

  @override
  State<PackManagerScreen> createState() => _PackManagerScreenState();
}

class _PackManagerScreenState extends State<PackManagerScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('管理主题与配色'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '主题包'),
              Tab(text: '课程配色'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[_buildThemeTab(), _buildPaletteTab()],
        ),
      ),
    );
  }

  // ───────────────────────── 列表 ─────────────────────────

  /// 「主题包」tab：内置在前、导入在后（数据来自 service.all）。
  Widget _buildThemeTab() {
    return ValueListenableBuilder<List<ThemePack>>(
      valueListenable: widget.themeService.imported,
      builder: (BuildContext context, List<ThemePack> imported, _) {
        return ValueListenableBuilder<ThemePack>(
          valueListenable: widget.themeService.active,
          builder: (BuildContext context, ThemePack active, _) {
            final List<ThemePack> packs = widget.themeService.all;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: packs.length,
              itemBuilder: (BuildContext context, int index) {
                final ThemePack pack = packs[index];
                final bool selected = pack == active;
                return _packRow(
                  preview: _themePreview(pack, selected),
                  name: pack.name,
                  builtin: pack.builtin,
                  selected: selected,
                  onSelect: () => widget.themeService.select(pack),
                  onMenuSelected: (String action) =>
                      _onThemeMenuSelected(action, pack),
                );
              },
            );
          },
        );
      },
    );
  }

  /// 「课程配色」tab：结构同主题 tab（`theme:` 临时包只在选择面板展示，
  /// 不进管理列表）。
  Widget _buildPaletteTab() {
    return ValueListenableBuilder<List<PalettePack>>(
      valueListenable: widget.paletteService.imported,
      builder: (BuildContext context, List<PalettePack> imported, _) {
        return ValueListenableBuilder<PalettePack>(
          valueListenable: widget.paletteService.active,
          builder: (BuildContext context, PalettePack active, _) {
            final List<PalettePack> packs = widget.paletteService.all;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: packs.length,
              itemBuilder: (BuildContext context, int index) {
                final PalettePack pack = packs[index];
                final bool selected = pack == active;
                return _packRow(
                  preview: PaletteSwatches(colors: pack.colors, size: 16),
                  name: pack.name,
                  builtin: pack.builtin,
                  selected: selected,
                  onSelect: () => widget.paletteService.select(pack),
                  onMenuSelected: (String action) =>
                      _onPaletteMenuSelected(action, pack),
                );
              },
            );
          },
        );
      },
    );
  }

  // ───────────────────────── 行 ─────────────────────────

  /// 主题包预览：36dp 圆形种子色块，选中套 onSurface 2dp 描边。
  Widget _themePreview(ThemePack pack, bool selected) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color(pack.seedColor),
        border: selected ? Border.all(color: colors.onSurface, width: 2) : null,
      ),
    );
  }

  /// 通用一行（主题 / 配色共用骨架，只有预览不同）。
  Widget _packRow({
    required Widget preview,
    required String name,
    required bool builtin,
    required bool selected,
    required VoidCallback onSelect,
    required ValueChanged<String> onMenuSelected,
  }) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      leading: preview,
      title: Text(
        name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        builtin ? '内置（不可修改）' : '导入',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (selected)
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多操作',
            onSelected: onMenuSelected,
            itemBuilder: (BuildContext context) => _menuEntries(builtin),
          ),
        ],
      ),
      onTap: onSelect,
    );
  }

  /// 菜单项：内置只有「复制 JSON」，导入多「重命名」「删除」。
  List<PopupMenuEntry<String>> _menuEntries(bool builtin) {
    return <PopupMenuEntry<String>>[
      if (!builtin)
        const PopupMenuItem<String>(value: 'rename', child: Text('重命名')),
      const PopupMenuItem<String>(value: 'copy', child: Text('复制 JSON')),
      if (!builtin)
        const PopupMenuItem<String>(value: 'delete', child: Text('删除')),
    ];
  }

  // ───────────────────────── 菜单动作 ─────────────────────────

  Future<void> _onThemeMenuSelected(String action, ThemePack pack) async {
    switch (action) {
      case 'rename':
        await _showRenameDialog(
          pack.name,
          (String newName) => widget.themeService.rename(pack, newName),
        );
      case 'copy':
        await _copyJson(pack.toJson());
      case 'delete':
        if (await _confirmDelete()) {
          await widget.themeService.remove(pack);
        }
    }
  }

  Future<void> _onPaletteMenuSelected(String action, PalettePack pack) async {
    switch (action) {
      case 'rename':
        await _showRenameDialog(
          pack.name,
          (String newName) => widget.paletteService.rename(pack, newName),
        );
      case 'copy':
        await _copyJson(pack.toJson());
      case 'delete':
        if (await _confirmDelete()) {
          await widget.paletteService.remove(pack);
        }
    }
  }

  // ───────────────────────── 对话框与反馈 ─────────────────────────

  /// 重命名对话框：预填当前名、autofocus；
  /// trim 后非空且与原名不同才提交，成功后 SnackBar。
  Future<void> _showRenameDialog(
    String currentName,
    Future<void> Function(String newName) onSubmit,
  ) async {
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _RenameDialog(initialName: currentName),
    );
    if (result == null || !mounted) {
      return;
    }
    final String newName = result.trim();
    if (newName.isEmpty || newName == currentName) {
      return;
    }
    await onSubmit(newName);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已重命名为「$newName」')));
  }

  /// 删除二次确认；返回是否确认。
  Future<bool> _confirmDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除'),
        content: const Text('删除后不可恢复，确定？'),
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
    return confirmed == true;
  }

  /// 复制为可再次导入的 JSON：toJson 的键就是 fromJson 接受的键
  /// （PalettePack.colors / ThemePack.seedColor 都是 ARGB int，
  /// 导入端 parseColor 接受 int，jsonEncode 后可直接往返）。
  Future<void> _copyJson(Map<String, dynamic> json) async {
    await Clipboard.setData(ClipboardData(text: jsonEncode(json)));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制到剪贴板，可发给同学导入')));
  }
}


/// 重命名对话框：**自己持有** TextEditingController，在 dispose 时释放。
///
/// ⚠️ 不要在 `await showDialog(...)` 之后立刻 dispose 外面创建的 controller：
/// showDialog 的 Future 在用户点击时就完成，此时对话框正在播退场动画，
/// TextField 还会重建并访问 controller，会抛
/// 「A TextEditingController was used after being disposed」（真机/测试都踩过）。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
