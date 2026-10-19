/// 课程配色选择面板（设置页「外观 → 课程配色」弹出）。
///
/// 与主题包面板共用同一套外壳零件（限宽 / 圆角 / 拖拽条 / 头卡 /
/// 动作行），保证所有底部弹窗的第一眼观感一致。
library;

import 'package:flutter/material.dart';

import 'package:timetable/models/palette_pack.dart';
import 'package:timetable/services/palette_service.dart';
import 'package:timetable/widgets/course_sheet_parts.dart';

/// 单个配色预览色块（22dp 方形、圆角 6）。
///
/// 公开成独立 widget 供测试计数（每行最多 6 个）。
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch({super.key, required this.color});

  final int color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Color(color),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// 一排配色预览（前 6 个颜色横向排列，间隔 4dp）。
///
/// 配色包的核心信息是「一排颜色」，必须让人一眼看出多色分布——
/// 不用单个圆形色块。宽度固定（6×22 + 5×4），不足 6 色时右侧留空。
class PaletteSwatches extends StatelessWidget {
  const PaletteSwatches({super.key, required this.colors});

  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    final List<int> shown = colors.take(6).toList(growable: false);
    return SizedBox(
      width: 6 * 22 + 5 * 4,
      child: Row(
        children: <Widget>[
          for (int i = 0; i < shown.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 4),
            PaletteSwatch(color: shown[i]),
          ],
        ],
      ),
    );
  }
}

/// 课程配色列表面板：内置在前、导入在后；若当前生效的是主题包带来的
/// 配色（`theme:` 前缀临时包），把它插在**最前面**让用户看得到。
class PalettePackSheet extends StatelessWidget {
  const PalettePackSheet({
    super.key,
    required this.service,
    required this.onImport,
  });

  final PaletteService service;

  /// 「导入配色…」动作（设置页实现：FilePicker → importFromJson →
  /// SnackBar 反馈；重取色由设置页对 paletteService.active 的监听统一处理）。
  final VoidCallback onImport;

  /// 弹出面板。isScrollControlled 让内容可以超过半屏（0.85 屏高上限）。
  static Future<void> show(
    BuildContext context, {
    required PaletteService service,
    required VoidCallback onImport,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: courseSheetShape,
      constraints: courseSheetConstraints,
      builder: (_) => PalettePackSheet(service: service, onImport: onImport),
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
              title: '课程配色',
              lines: <String>['选一套课块配色，课表与小组件会一起换'],
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 4),
                children: <Widget>[
                  ValueListenableBuilder<List<PalettePack>>(
                    valueListenable: service.imported,
                    builder:
                        (BuildContext context, List<PalettePack> imported, _) {
                          return ValueListenableBuilder<PalettePack>(
                            valueListenable: service.active,
                            builder:
                                (BuildContext context, PalettePack active, _) {
                                  final List<PalettePack> rows = <PalettePack>[
                                    if (active.id.startsWith('theme:')) active,
                                    ...PalettePack.builtins,
                                    ...imported,
                                  ];
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      for (final PalettePack pack in rows)
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
                    title: '导入配色…',
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

  /// 一行配色：一排色块预览 + 名称 + 来源标注 + 选中态
  /// （导入项可删；主题包临时包仅展示、不可点选）。
  Widget _packRow(BuildContext context, PalettePack pack, PalettePack active) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    // 值语义判等（PalettePack 重写过 ==，含全部字段）
    final bool selected = pack == active;
    final bool fromTheme = pack.id.startsWith('theme:');
    final Widget? check = selected
        ? Icon(Icons.check_circle, color: colors.primary)
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: PaletteSwatches(colors: pack.colors),
      title: Text(
        pack.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        fromTheme ? '主题包' : (pack.builtin ? '内置' : '导入'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      trailing: fromTheme
          ? check
          : pack.builtin
          ? check
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[?check,
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除配色',
                  onPressed: () => service.remove(pack),
                ),
              ],
            ),
      // 主题包临时包只是「当前生效」的展示，点了没有意义；
      // 其余（内置 / 导入）点选即生效
      onTap: fromTheme ? null : () => service.select(pack),
    );
  }
}
