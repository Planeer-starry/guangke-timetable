/// 主题包选择面板（设置页「外观 → 主题包」弹出）。
///
/// 与课程操作面板共用同一套外壳零件（限宽 / 圆角 / 拖拽条 / 头卡 /
/// 动作行），保证所有底部弹窗的第一眼观感一致。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/services/theme_service.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';
import 'package:timetable/widgets/pack_actions.dart';

/// 主题包列表面板：内置在前、导入在后，点选即生效；
/// 「导入主题包…」走文件选择（回调由设置页提供）。
class ThemePackSheet extends StatelessWidget {
  const ThemePackSheet({
    super.key,
    required this.service,
    required this.onImport,
  });

  final ThemeService service;

  /// 「导入主题包…」动作（设置页实现：FilePicker → importFromJson →
  /// SnackBar 反馈；重新取色由设置页对 active 的监听统一处理）。
  final VoidCallback onImport;

  /// 弹出面板。isScrollControlled 让内容可以超过半屏（0.85 屏高上限）。
  static Future<void> show(
    BuildContext context, {
    required ThemeService service,
    required VoidCallback onImport,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: courseSheetShape,
      constraints: courseSheetConstraints,
      builder: (_) => ThemePackSheet(service: service, onImport: onImport),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SheetDragHandle(),
            SheetHeaderCard(
              color: colors.primary,
              title: '主题包',
              lines: <String>['选一套配色，界面 / 课块 / 小组件高亮会一起变'],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 4),
                children: <Widget>[
                  ValueListenableBuilder<List<ThemePack>>(
                    valueListenable: service.imported,
                    builder:
                        (BuildContext context, List<ThemePack> imported, _) {
                          return ValueListenableBuilder<ThemePack>(
                            valueListenable: service.active,
                            builder:
                                (BuildContext context, ThemePack active, _) {
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      for (final ThemePack pack
                                          in ThemePack.builtins)
                                        _packRow(context, pack, active),
                                      for (final ThemePack pack in imported)
                                        _packRow(context, pack, active),
                                    ],
                                  );
                                },
                          );
                        },
                  ),
                  const SheetDivider(),
                  SheetActionRow(
                    icon: Icons.file_download_outlined,
                    title: '导入主题包…',
                    subtitle: '选择 .json 文件，立刻生效',
                    onTap: () {
                      // 先关面板再走文件选择：file picker 是全屏 Activity，
                      // 返回后的 SnackBar 反馈不能被底部弹窗盖住
                      Navigator.of(context).pop();
                      onImport();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一行主题包：36dp 色块 + 名称 + 来源标注 + 选中态
  /// （行尾「⋯」菜单：内置仅复制，导入可重命名 / 复制 / 删除）。
  Widget _packRow(BuildContext context, ThemePack pack, ThemePack active) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    // 值语义判等（ThemePack 重写过 ==，含全部字段）
    final bool selected = pack == active;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Color(pack.seedColor),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: colors.onSurface, width: 2)
              : null,
        ),
      ),
      title: Text(
        pack.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        pack.builtin
            ? '内置'
            : (pack.coursePalette != null ? '导入 · 含课程配色' : '导入'),
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (selected) Icon(Icons.check_circle, color: colors.primary),
          PackActionsButton(
            builtin: pack.builtin,
            onRename: () async {
              final String? input = await showRenamePackDialog(
                context,
                initialName: pack.name,
              );
              if (input == null || !context.mounted) {
                return;
              }
              final String newName = input.trim();
              if (newName.isEmpty || newName == pack.name) {
                return;
              }
              await service.rename(pack, newName);
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('已重命名为「$newName」')));
            },
            onCopyJson: () => copyPackJson(context, jsonEncode(pack.toJson())),
            onDelete: () async {
              if (!await confirmDeletePack(context)) {
                return;
              }
              await service.remove(pack);
            },
          ),
        ],
      ),
      onTap: () => service.select(pack),
    );
  }
}
