package com.planeer.timetable

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONArray

/**
 * 「今日课程」小组件（与「下节课」同一设计语言）。
 *
 * 单一真源在 Dart 侧：未来 7 天每天一个分组（含表头与课程行）由 Dart
 * 纯函数算好，经 home_widget 存到 `today_days` / `today_empty_text`。
 * 这里只做「按今天日期挑一组 + 渲染」，不碰任何课程 / 周次逻辑。
 * 存 7 天分组的原因：跨天 0 点触发的是 onUpdate（不重跑 Dart），
 * 按日期挑组才能跨天自动正确。
 *
 * 结构固定、内容左对齐：表头（日期 · 周次）永远显示；主体区有课逐行渲染，
 * 没课左对齐一行文案。文字颜色默认由布局引用共享 token
 * （values / values-night 自动切换）；J9 皮肤在场时卡片 tint 与
 * 文字色改走皮肤，这里只填文字内容与色条课程色。
 */
class TodayWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val today = LocalDate.now().toString() // "2026-10-17"，与 Dart dateKey 对齐
    val groups = parseGroups(widgetData.getString(KEY_DAYS, null))
    // J9 皮肤：在场时卡片 tint + 文字色跟随主题包，否则回退 res 资源
    val skin = WidgetColors.skinOf(widgetData, context)
    val accentColor = skin?.accent ?: WidgetColors.accentOf(widgetData, context)

    for (appWidgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.today_widget)
      if (skin != null) {
        WidgetColors.applyCardTint(views, R.id.today_widget_root, skin.card)
        views.setTextColor(R.id.today_header, skin.sub)
        views.setTextColor(R.id.today_empty, skin.title)
      }
      val group = groups.firstOrNull { it.date == today }

      if (group != null && group.items.isNotEmpty()) {
        renderList(context, views, group, accentColor, skin?.title, skin?.sub)
      } else {
        renderEmpty(views, group, widgetData)
      }
      // 点击整个组件打开 App（与「一周总课表」一致）。
      // home_widget 0.10.0 的签名是 getActivity(context, activityClass, uri)，
      // 必须显式传 activityClass，没有只接受 context 的重载。
      views.setOnClickPendingIntent(
          R.id.today_widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }

  /**
   * 系统深浅色切换时重渲染。
   *
   * RemoteViews 里的 setTextColor / setBackgroundTintList 是**渲染那一刻写死的
   * 常量**，不像布局里的 `@color` 那样跟随 values-night 自动变化；系统切深浅色
   * 时也不会主动重跑 onUpdate。不在这里主动刷一次，小组件会一直停在旧配色上
   * （用户报的「小组件不跟随深浅色」）。
   *
   * 兜底：Android 8+ 对静态注册的隐式广播有限制，CONFIGURATION_CHANGED 不一定
   * 每次都送达；appwidget-provider 里的 updatePeriodMillis（30 分钟）与
   * App 启动 / 改主题时的主动刷新会补上。
   */
  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action != Intent.ACTION_CONFIGURATION_CHANGED) {
      return
    }
    val manager = AppWidgetManager.getInstance(context)
    val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
    if (ids.isNotEmpty()) {
      onUpdate(context, manager, ids, HomeWidgetPlugin.getData(context))
    }
  }

  /** 列表态：表头 + 动态课程行（最多 [MAX_ROWS] 行，超出显示「还有 N 节」）。 */
  private fun renderList(
      context: Context,
      views: RemoteViews,
      group: DayGroup,
      accentColor: Int,
      titleColor: Int?,
      subColor: Int?,
  ) {
    views.setViewVisibility(R.id.today_rows, View.VISIBLE)
    views.setViewVisibility(R.id.today_empty, View.GONE)
    views.setTextViewText(R.id.today_header, group.header)

    views.removeAllViews(R.id.today_rows)
    val shown = group.items.take(MAX_ROWS)
    for (item in shown) {
      val row = RemoteViews(context.packageName, R.layout.today_widget_row)
      row.setTextViewText(R.id.row_time, item.timeText)
      row.setTextViewText(R.id.row_title, item.title)
      row.setTextViewText(R.id.row_location, item.location)
      row.setInt(R.id.row_color, "setBackgroundColor", item.color)
      if (titleColor != null) {
        row.setTextColor(R.id.row_title, titleColor)
      }
      if (subColor != null) {
        row.setTextColor(R.id.row_time, subColor)
        row.setTextColor(R.id.row_location, subColor)
      }
      views.addView(R.id.today_rows, row)
    }
    val remaining = group.items.size - shown.size
    if (remaining > 0) {
      val more = RemoteViews(context.packageName, R.layout.today_widget_more)
      more.setTextViewText(R.id.more_text, "还有 $remaining 节")
      if (subColor != null) {
        more.setTextColor(R.id.more_text, subColor)
      }
      views.addView(R.id.today_rows, more)
    }
  }

  /**
   * 空状态（结构不变、内容左对齐）：
   * - 找到日期组但没课 → 表头照常 + 「今天没有课」；
   * - 找不到（未同步/数据过期）→ 表头兜底「今日课程」+ Dart 存的空文案。
   */
  private fun renderEmpty(
      views: RemoteViews,
      group: DayGroup?,
      widgetData: SharedPreferences,
  ) {
    views.setViewVisibility(R.id.today_rows, View.GONE)
    views.setViewVisibility(R.id.today_empty, View.VISIBLE)

    if (group != null) {
      views.setTextViewText(R.id.today_header, group.header)
      views.setTextViewText(R.id.today_empty, "今天没有课")
    } else {
      views.setTextViewText(R.id.today_header, "今日课程")
      views.setTextViewText(
          R.id.today_empty,
          widgetData.getString(KEY_EMPTY_TEXT, null) ?: "打开 App 同步课表")
    }
  }

  private data class DayItem(
      val timeText: String,
      val title: String,
      val location: String,
      val color: Int,
  )

  private data class DayGroup(val date: String, val header: String, val items: List<DayItem>)

  private fun parseGroups(json: String?): List<DayGroup> {
    if (json.isNullOrEmpty()) {
      return emptyList()
    }
    return runCatching {
      val array = JSONArray(json)
      (0 until array.length()).mapNotNull { index ->
        val group = array.optJSONObject(index) ?: return@mapNotNull null
        val itemsArray = group.optJSONArray("items") ?: JSONArray()
        DayGroup(
            date = group.optString("date"),
            header = group.optString("header"),
            items =
                (0 until itemsArray.length()).mapNotNull { itemIndex ->
                  val item = itemsArray.optJSONObject(itemIndex) ?: return@mapNotNull null
                  DayItem(
                      timeText = item.optString("timeText"),
                      title = item.optString("title"),
                      location = item.optString("location"),
                      // Dart 的 ARGB int 是 64 位，可能超过 Kotlin Int.MAX；
                      // 必须 toLong 再 toInt，32 位 ARGB 位模式才正确
                      color = item.optString("color").toLongOrNull()?.toInt() ?: 0,
                  )
                },
        )
      }
    }.getOrDefault(emptyList())
  }

  private companion object {
    const val KEY_DAYS = "today_days"
    const val KEY_EMPTY_TEXT = "today_empty_text"

    /** 2 行高组件最多渲染 4 行，超出显示「还有 N 节」。 */
    const val MAX_ROWS = 4
  }
}