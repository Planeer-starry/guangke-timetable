package com.planeer.timetable

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 「下节课」小组件（2 行高，与「今日课程」同一设计语言）。
 *
 * 单一真源在 Dart 侧：候选列表（未来若干天的节次，含绝对时刻）由 Dart 纯函数算好，
 * 经 home_widget 存到 `next_items` / `next_empty_text`。这里只做
 * 「按当前时间挑一条 + 拼字符串」，不碰任何课程 / 周次逻辑。
 *
 * 文字颜色全部由布局引用共享 token（values / values-night 自动切换），
 * 这里只负责文字内容与左侧色条的课程色。
 */
class NextClassWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val now = System.currentTimeMillis()
    // 空态色条用主题包强调色（课程色兜底也用它）
    val accentColor = WidgetColors.accentOf(widgetData, context)
    val items = parseItems(widgetData.getString(KEY_ITEMS, null), accentColor)
    // 键缺失（从未同步过）→ 默认「打开 App 同步课表」
    val emptyText = widgetData.getString(KEY_EMPTY_TEXT, null) ?: "打开 App 同步课表"

    for (appWidgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.next_class_widget)
      val pick = items.firstOrNull { it.endMs > now }
      if (pick == null) {
        views.setTextViewText(R.id.next_title, emptyText)
        views.setTextViewText(R.id.next_sub, "")
        views.setInt(R.id.next_color, "setBackgroundColor", accentColor)
      } else if (pick.startMs <= now) {
        views.setTextViewText(R.id.next_title, pick.title)
        views.setTextViewText(
            R.id.next_sub, "进行中 · ${pick.endText} 下课 · ${pick.location}")
        views.setInt(R.id.next_color, "setBackgroundColor", pick.color)
      } else {
        views.setTextViewText(R.id.next_title, pick.title)
        views.setTextViewText(R.id.next_sub, "${pick.whenText} · ${pick.location}")
        views.setInt(R.id.next_color, "setBackgroundColor", pick.color)
      }
      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }

  private data class Item(
      val title: String,
      val whenText: String,
      val endText: String,
      val location: String,
      val color: Int,
      val startMs: Long,
      val endMs: Long,
  )

  private fun parseItems(json: String?, fallbackColor: Int): List<Item> {
    if (json.isNullOrEmpty()) {
      return emptyList()
    }
    return runCatching {
      val array = org.json.JSONArray(json)
      (0 until array.length()).mapNotNull { index ->
        val item = array.optJSONObject(index) ?: return@mapNotNull null
        Item(
            title = item.optString("title"),
            whenText = item.optString("whenText"),
            endText = item.optString("endText"),
            location = item.optString("location"),
            // Dart 的 ARGB int 是 64 位，可能超过 Kotlin Int.MAX；
            // 必须 toLong 再 toInt，32 位 ARGB 位模式才正确
            color = item.optString("color").toLongOrNull()?.toInt() ?: fallbackColor,
            startMs = item.optLong("startMs"),
            endMs = item.optLong("endMs"))
      }
    }.getOrDefault(emptyList())
  }

  private companion object {
    const val KEY_ITEMS = "next_items"
    const val KEY_EMPTY_TEXT = "next_empty_text"
  }
}