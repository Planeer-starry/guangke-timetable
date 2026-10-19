import 'package:home_widget/home_widget.dart';
import 'package:timetable/models/theme_pack.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/utils/next_class.dart';
import 'package:timetable/utils/today_classes.dart';
import 'package:timetable/utils/week_grid_model.dart';

/// 桌面小组件数据同步（封装 home_widget，UI 层不直接碰它的 API）。
///
/// 数据流：Dart 算好展示数据 → `saveWidgetData` 存储 →
/// `scheduleWidgetUpdates` 定时刷新（跨天 0 点与节次切换）→
/// `updateWidget` 立即渲染。Kotlin 侧只做「按当前时间/日期挑数据 +
/// 拼字符串渲染」，不承担业务逻辑。
class WidgetService {
  WidgetService._();

  /// 「下节课」Android 侧 AppWidgetProvider 类名
  /// （home_widget 会拼成 `包名.类名` 解析）。
  static const String nextProviderName = 'NextClassWidgetProvider';

  /// 「今日课程」Android 侧 AppWidgetProvider 类名。
  static const String todayProviderName = 'TodayWidgetProvider';

  /// 「一周总课表」Android 侧 AppWidgetProvider 类名。
  static const String weekProviderName = 'WeekWidgetProvider';

  static const String _keyNextItems = 'next_items';
  static const String _keyNextEmptyText = 'next_empty_text';
  static const String _keyTodayDays = 'today_days';
  static const String _keyTodayEmptyText = 'today_empty_text';
  static const String _keyWeekGrids = 'week_grids';
  static const String _keyWeekEmptyText = 'week_empty_text';
  static const String _keyAccent = 'widget_accent';

  /// 当前小组件强调色（ARGB int）；null = 从未设置过主题包
  /// （写空串，Kotlin 侧 toLongOrNull 得 null 回退资源色）。
  ///
  /// 由 main 启动 + 设置页主题切换时 [setAccent] 更新（J6）。
  /// ⚠️ 卡片背景色 / 文字色**不**跟随主题包：RemoteViews 无法设置
  /// 程序化创建的圆角 Drawable，改纯色会丢圆角；文字跟着变有对比度风险。
  static int? _accentValue;

  /// 按主题包设置小组件强调色（`widgetAccent ?? seedColor`）。
  static void setAccent(ThemePack pack) {
    _accentValue = pack.widgetAccent ?? pack.seedColor;
  }

  /// 重新计算候选并同步「下节课」小组件。
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
      _keyNextItems,
      NextCandidate.encodeList(candidates),
    );
    // 三种空状态：键缺失 → Kotlin 默认「打开 App 同步课表」；
    // 学期未配置 → 「请先设置学期」；已配置但无候选 → 「暂无课程」。
    await HomeWidget.saveWidgetData<String>(
      _keyNextEmptyText,
      data.semesterConfigured ? '暂无课程' : '请先设置学期',
    );
    if (schedule) {
      await HomeWidget.scheduleWidgetUpdates(
        widgetUpdateTimes(data, at),
        androidName: nextProviderName,
      );
    }
    await HomeWidget.updateWidget(androidName: nextProviderName);
  }

  /// 重新计算未来 7 天分组并同步「今日课程」小组件。
  ///
  /// 存 7 天分组而非当天快照：跨天 0 点触发的是 Kotlin 的 onUpdate
  /// （不重跑 Dart），按日期挑组才能跨天自动正确。
  static Future<void> refreshToday(
    TimetableData data, {
    DateTime? now,
    bool schedule = true,
  }) async {
    final DateTime at = now ?? DateTime.now();
    final List<TodayGroup> groups = todayGroups(data, at);
    await HomeWidget.saveWidgetData<String>(
      _keyTodayDays,
      TodayGroup.encodeList(groups),
    );
    // 空状态（Kotlin 找不到今天分组时显示）：
    // 学期未配置 → 「请先设置学期」；已配置 → 数据过期兜底「打开 App 同步课表」。
    await HomeWidget.saveWidgetData<String>(
      _keyTodayEmptyText,
      data.semesterConfigured ? '打开 App 同步课表' : '请先设置学期',
    );
    if (schedule) {
      await HomeWidget.scheduleWidgetUpdates(
        _midnightTimes(at),
        androidName: todayProviderName,
      );
    }
    await HomeWidget.updateWidget(androidName: todayProviderName);
  }

  /// 一次刷新「下节课」+「今日课程」+「一周总课表」三个小组件
  /// （App 内所有数据变更点用它）。
  static Future<void> refreshAll(
    TimetableData data, {
    DateTime? now,
    bool schedule = true,
  }) async {
    // 主题包强调色（与课程色同套路：ARGB int 的十进制字符串，
    // Kotlin 侧 toLongOrNull 再 toInt 还原 32 位位模式）
    await HomeWidget.saveWidgetData<String>(
      _keyAccent,
      _accentValue?.toString() ?? '',
    );
    await refreshNextClass(data, now: now, schedule: schedule);
    await refreshToday(data, now: now, schedule: schedule);
    await refreshWeek(data, now: now, schedule: schedule);
  }

  /// 重新计算未来 3 周网格并同步「一周总课表」小组件。
  ///
  /// 存 3 周快照而非只存本周：跨周 0 点触发的是 Kotlin 的 onUpdate
  /// （不重跑 Dart），按日期挑周才能跨周自动正确——否则下周一凌晨
  /// 组件会一直显示上一周的课表。
  static Future<void> refreshWeek(
    TimetableData data, {
    DateTime? now,
    bool schedule = true,
  }) async {
    final DateTime at = now ?? DateTime.now();
    final List<WeekSnapshot> snapshots = weekSnapshots(data, at);
    await HomeWidget.saveWidgetData<String>(
      _keyWeekGrids,
      weekGridsEncode(snapshots),
    );
    // 空状态（Kotlin 找不到本周快照 / 本周全空时显示）：
    // 学期未配置 → 「请先设置学期」；已配置 → 「本周没有课」。
    await HomeWidget.saveWidgetData<String>(
      _keyWeekEmptyText,
      data.semesterConfigured ? '本周没有课' : '请先设置学期',
    );
    if (schedule) {
      await HomeWidget.scheduleWidgetUpdates(
        _mondayMidnightTimes(at),
        androidName: weekProviderName,
      );
    }
    await HomeWidget.updateWidget(androidName: weekProviderName);
  }

  /// 「一周总课表」的定时刷新时刻：未来 3 个周一 0 点（跨周切快照）。
  /// 本周一 0 点已过去，home_widget 会忽略过去时刻。
  static List<DateTime> _mondayMidnightTimes(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    int daysToNextMonday = (DateTime.monday - today.weekday + 7) % 7;
    if (daysToNextMonday == 0) {
      daysToNextMonday = 7; // 今天是周一：今天 0 点已过，从下周一起
    }
    return List<DateTime>.generate(
      3,
      (int i) => today.add(Duration(days: daysToNextMonday + 7 * i)),
    );
  }

  /// 「今日课程」的定时刷新时刻：未来 7 天每个 0 点（跨天切组）。
  /// 今天的 0 点已过去，home_widget 会忽略过去时刻。
  static List<DateTime> _midnightTimes(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return List<DateTime>.generate(
      7,
      (int i) => today.add(Duration(days: i + 1)),
    );
  }
}
