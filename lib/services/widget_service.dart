import 'package:home_widget/home_widget.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/next_class.dart';

/// 桌面小组件数据同步（封装 home_widget，UI 层不直接碰它的 API）。
///
/// 数据流：Dart 算好候选列表 → `saveWidgetData` 存 `next_items` /
/// `next_empty_text` → `scheduleWidgetUpdates`（跨天 0 点与每节上下课自动刷新）
/// → `updateWidget` 立即渲染。
/// Kotlin 侧只做「按当前时间挑一条 + 拼字符串」，不承担业务逻辑。
class WidgetService {
  WidgetService._();

  /// Android 侧 AppWidgetProvider 的类名（不含包名前缀，
  /// home_widget 会拼成 `包名.类名` 解析）。
  static const String androidProviderName = 'NextClassWidgetProvider';

  static const String _keyItems = 'next_items';
  static const String _keyEmptyText = 'next_empty_text';

  /// 重新计算候选并同步到小组件。
  ///
  /// [now] 可注入（测试用）；[schedule] 控制是否设置定时刷新（测试可关）。
  static Future<void> refreshNextClass(
    TimetableData data, {
    DateTime? now,
    bool schedule = true,
  }) async {
    final DateTime at = now ?? DateTime.now();
    final List<NextCandidate> candidates = nextCandidates(data, at);
    await HomeWidget.saveWidgetData<String>(
      _keyItems,
      NextCandidate.encodeList(candidates),
    );
    // 三种空状态：键缺失 → Kotlin 默认「打开 App 同步课表」；
    // 学期未配置 → 「请先设置学期」；已配置但无候选 → 「暂无课程」。
    await HomeWidget.saveWidgetData<String>(
      _keyEmptyText,
      data.semesterConfigured ? '暂无课程' : '请先设置学期',
    );
    if (schedule) {
      await HomeWidget.scheduleWidgetUpdates(
        widgetUpdateTimes(data, at),
        androidName: androidProviderName,
      );
    }
    await HomeWidget.updateWidget(androidName: androidProviderName);
  }
}
