import 'package:flutter/material.dart';

/// 卡片背景色。
///
/// **亮色用纯白**：页面背景是淡灰，白色卡片浮在上面层次清楚；
/// 若卡片也用灰（surfaceContainerHigh），整页会糊成一片灰——
/// 编辑页三张卡片占满屏幕时尤其明显。
///
/// **暗色用高容器色**：暗色下白色卡片会刺眼，且 surfaceContainerLowest
/// 在暗色里就是纯黑，比背景还暗、看不出边界，所以反过来取比背景亮一档。
Color appCardColor(ColorScheme colors) {
  return colors.brightness == Brightness.light
      ? colors.surfaceContainerLowest
      : colors.surfaceContainerHigh;
}

/// 页面背景色：亮色用一档淡灰，让白色卡片浮起来；暗色沿用主题默认。
Color? appPageBackground(ColorScheme colors) {
  return colors.brightness == Brightness.light
      ? colors.surfaceContainerLow
      : null;
}

/// 统一的卡片容器：白（亮）/ 高容器色（暗）底 + 1dp 描边 + 16dp 圆角。
///
/// 设置页、课程编辑页等「分组表单 / 设置项」都用它，保证跨页面视觉一致。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    this.title,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  /// 分组标题（primary 色加粗），null = 不显示标题。
  final String? title;

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isLight = colors.brightness == Brightness.light;
    final String? heading = title;
    return Card(
      // 亮色加一点投影让白卡片浮起来；暗色靠描边就够，投影会脏
      elevation: isLight ? 1 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      margin: EdgeInsets.zero,
      color: appCardColor(colors),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (heading != null) ...<Widget>[
              Text(
                heading,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// 卡片内的小节标签（比 AppCard.title 低一档，用于「星期」「节次」等）。
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget? tail = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (tail != null) ...<Widget>[const Spacer(), tail],
        ],
      ),
    );
  }
}
