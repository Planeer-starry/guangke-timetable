import 'package:flutter/material.dart';

/// 窗口尺寸断点（Material 3 窗口尺寸类的简化版）。
///
/// compact = 手机竖屏；medium = 手机横屏 / 折叠屏 / 小平板；
/// expanded = 平板。在页面顶层调用一次往下传，
/// 子 widget 不要各自读 MediaQuery。
enum WindowSize { compact, medium, expanded }

/// 按逻辑宽度取断点。
WindowSize windowSizeOf(BuildContext context) {
  final double w = MediaQuery.sizeOf(context).width;
  if (w >= 840) {
    return WindowSize.expanded;
  }
  if (w >= 600) {
    return WindowSize.medium;
  }
  return WindowSize.compact;
}

/// 断点便捷判断扩展。
extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool get isExpanded => this == WindowSize.expanded;
}
