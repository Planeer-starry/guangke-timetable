package com.planeer.timetable

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONArray

/**
 * 「今日课程」小组件。
 *
 * 单一真源在 Dart 侧：未来 7 天每天一个分组（含表头与课程行）由 Dart
 * 纯函数算好，经 home_widget 存到 `today_days` / `today_empty_text`。
 * 这里只做「按今天日期挑一组 + 渲染」，不碰任何课程 / 周次逻辑。
 * 存 7 天分组的原因：跨天 0 点触发的是 onUpdate（不重跑 Dart），
 * 按日期挑组才能跨天自动正确。
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
    val dark =
        (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
    val textPrimary = if (dark) COLOR_TEXT_PRIMARY_DARK else COLOR_TEXT_PRIMARY_LIGHT
    val textSecondary = if (dark) COLOR_TEXT_SECONDARY_DARK else COLOR_TEXT_SECONDARY_LIGHT

    for (appWidgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.today_widget)
      val group = groups.firstOrNull { it.date == today }

      if (group != null && group.items.isNotEmpty()) {
        renderList(context, views, group, textPrimary, textSecondary)
      } else {
        renderEmpty(views, group, widgetData, textPrimary, textSecondary)
      }
      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }

  /** 列表态：表头 + 动态课程行（最多 [MAX_ROWS] 行，超出显示「还有 N 节」）。 */
  private fun renderList(
      context: Context,
      views: RemoteViews,
      group: DayGroup,
      textPrimary: Int,
      textSecondary: Int,
  ) {
    views.setViewVisibility(R.id.today_header, View.VISIBLE)
    views.setViewVisibility(R.id.today_rows, View.VISIBLE)
    views.setViewVisibility(R.id.today_empty, View.GONE)
    views.setTextViewText(R.id.today_header, group.header)
    views.setTextColor(R.id.today_header, textSecondary)

    views.removeAllViews(R.id.today_rows)
    val shown = group.items.take(MAX_ROWS)
    for (item in shown) {
      val row = RemoteViews(context.packageName, R.layout.today_widget_row)
      row.setTextViewText(R.id.row_time, item.timeText)
      row.setTextViewText(R.id.row_title, item.title)
      row.setTextViewText(R.id.row_location, item.location)
      row.setTextColor(R.id.row_time, textSecondary)
      row.setTextColor(R.id.row_title, textPrimary)
      row.setTextColor(R.id.row_location, textSecondary)
      row.setInt(R.id.row_color, "setBackgroundColor", item.color)
      views.addView(R.id.today_rows, row)
    }
    val remaining = group.items.size - shown.size
    if (remaining > 0) {
      val more = RemoteViews(context.packageName, R.layout.today_widget_more)
      more.setTextViewText(R.id.more_text, "还有 $remaining 节")
      more.setTextColor(R.id.more_text, textSecondary)
      views.addView(R.id.today_rows, more)
    }
  }

  /** 空状态：图标 + 主文案 +（有日期信息时的）小字提示。 */
  private fun renderEmpty(
      views: RemoteViews,
      group: DayGroup?,
      widgetData: SharedPreferences,
      textPrimary: Int,
      textSecondary: Int,
  ) {
    views.setViewVisibility(R.id.today_header, View.GONE)
    views.setViewVisibility(R.id.today_rows, View.GONE)
    views.setViewVisibility(R.id.today_empty, View.VISIBLE)

    // 找到日期组但没课 → 「今天没有课」；找不到（未同步/过期）→ Dart 存的空文案
    val mainText =
        if (group != null) "今天没有课"
        else widgetData.getString(KEY_EMPTY_TEXT, null) ?: "打开 App 同步课表"
    views.setTextViewText(R.id.empty_title, mainText)
    views.setTextColor(R.id.empty_title, textPrimary)

    if (group != null) {
      // 没课的日子用日期表头当小字提示
      views.setViewVisibility(R.id.empty_subtitle, View.VISIBLE)
      views.setTextViewText(R.id.empty_subtitle, group.header)
      views.setTextColor(R.id.empty_subtitle, textSecondary)
    } else {
      views.setViewVisibility(R.id.empty_subtitle, View.GONE)
    }
    views.setInt(R.id.empty_icon, "setColorFilter", textSecondary)
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
                      color =
                          item.optString("color").toLongOrNull()?.toInt()
                              ?: COLOR_DEFAULT,
                  )
                },
        )
      }
    }.getOrDefault(emptyList())
  }

  private companion object {
    const val KEY_DAYS = "today_days"
    const val KEY_EMPTY_TEXT = "today_empty_text"
    const val MAX_ROWS = 5
    val COLOR_DEFAULT = 0xFF5C6BC0.toInt()

    // M3 基准色板（亮 / 暗两套，onSurface 与 onSurfaceVariant）
    val COLOR_TEXT_PRIMARY_LIGHT = 0xFF1D1B20.toInt()
    val COLOR_TEXT_PRIMARY_DARK = 0xFFE6E1E5.toInt()
    val COLOR_TEXT_SECONDARY_LIGHT = 0xFF49454E.toInt()
    val COLOR_TEXT_SECONDARY_DARK = 0xFFCAC4D0.toInt()
  }
}