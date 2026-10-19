/// 包行尾部的管理动作（J8 返工）：主题包 / 配色包两个面板共用的
/// 「⋯」菜单、重命名对话框、复制 JSON 与删除确认。
///
/// 只做纯 UI 动作，不依赖具体模型类型——包数据的读写由调用方经回调注入。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 菜单项标识（私有枚举，面板侧只见回调）。
enum _PackAction { rename, copy, delete }

/// 包行尾部的「⋯」菜单。
///
/// 内置包只给「复制 JSON」（方便以内置为基础改一份自定义的）；
/// 导入包给「重命名 / 复制 JSON / 删除」。
class PackActionsButton extends StatelessWidget {
  const PackActionsButton({
    super.key,
    required this.builtin,
    required this.onRename,
    required this.onCopyJson,
    required this.onDelete,
  });

  /// 是否内置包（内置不显示重命名 / 删除）。
  final bool builtin;

  /// 「重命名」动作（builtin 时不显示该菜单项）。
  final VoidCallback onRename;

  /// 「复制 JSON」动作。
  final VoidCallback onCopyJson;

  /// 「删除」动作（builtin 时不显示该菜单项）。
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return PopupMenuButton<_PackAction>(
      icon: Icon(Icons.more_vert, size: 20, color: colors.onSurfaceVariant),
      tooltip: '更多操作',
      onSelected: (_PackAction action) {
        switch (action) {
          case _PackAction.rename:
            onRename();
          case _PackAction.copy:
            onCopyJson();
          case _PackAction.delete:
            onDelete();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_PackAction>>[
        if (!builtin)
          const PopupMenuItem<_PackAction>(
            value: _PackAction.rename,
            child: Text('重命名'),
          ),
        const PopupMenuItem<_PackAction>(
          value: _PackAction.copy,
          child: Text('复制 JSON'),
        ),
        if (!builtin)
          const PopupMenuItem<_PackAction>(
            value: _PackAction.delete,
            child: Text('删除'),
          ),
      ],
    );
  }
}

/// 重命名对话框：返回用户输入的新名（取消返回 null）。
///
/// trim / 空白 / 与原名相同的判断由调用方做，这里只负责输入与返回。
Future<String?> showRenamePackDialog(
  BuildContext context, {
  required String initialName,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _RenamePackDialog(initialName: initialName),
  );
}

/// 重命名对话框本体。
///
/// ⚠️ TextEditingController 必须由对话框自己的 State 持有并在 dispose 释放：
/// showDialog 的 Future 在用户点击按钮的那一刻就完成，此时路由退场动画
/// 还在进行、TextField 仍会重建并访问 controller —— 若由调用方在 await
/// 之后 dispose，会抛 used after being disposed。State.dispose 在退场
/// 动画结束后才触发，是安全时机。
class _RenamePackDialog extends StatefulWidget {
  const _RenamePackDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePackDialog> createState() => _RenamePackDialogState();
}

class _RenamePackDialogState extends State<_RenamePackDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

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

/// 删除二次确认；返回是否确认删除。
Future<bool> confirmDeletePack(BuildContext context) async {
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

/// 把一个包的 JSON 复制到剪贴板并提示。
///
/// payload 由调用方传（`jsonEncode(pack.toJson())`——toJson 的键与
/// fromJson 对齐，复制出的文本可直接再次导入）。
Future<void> copyPackJson(BuildContext context, String payload) async {
  await Clipboard.setData(ClipboardData(text: payload));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('已复制到剪贴板，可发给同学导入')));
}
