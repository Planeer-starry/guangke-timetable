package com.planeer.timetable

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.time.LocalDate
import org.json.JSONArray
import org.json.JSONObject

/**
 * 「一周总课表」小组件（6×4 网格）。
 *
 * 单一真源在 Dart 侧：未来 3 周的网格快照（5 行 × 7 格，含日期与周次）由
 * Dart 纯函数算好，经 home_widget 存到 `week_grids` / `week_empty_text`。
 * 这里只做「按今天日期挑一周 + 渲染」，不碰任何课程 / 周次逻辑。
 * 存 3 周快照的原因：跨周 0 点触发的是 onUpdate（不重跑 Dart），
 * 按日期挑周才能跨周自动正确。
 *
 * 渲染用 2 层 addView：row 自带 week_cells 容器
 * （RemoteViews 只能按 layoutId 构造，不能按 viewId 构造）：
 * cell → rowRv.addView(week_cells) → views.addView(week_rows, rowRv)。
 */
class WeekWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val today = LocalDate.now()
    val weeks = parseWeeks(widgetData.getString(KEY_GRIDS, null))
    val week = weeks.firstOrNull { w ->
      val start = runCatching { LocalDate.parse(w.weekStart) }.getOrNull()
      start != null && !today.isBefore(start) && today.isBefore(start.plusDays(7))
    }
    val emptyColor = ContextCompat.getColor(context, R.color.widget_grid_empty)
    val accentColor = WidgetColors.accentOf(widgetData, context)
    // 今天列的高亮：accent 的半透明版本
    val highlightColor = (accentColor and 0x00FFFFFF) or (0x33 shl 24)

    for (appWidgetId in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.week_widget)
      if (week != null && week.hasAnyCourse()) {
        renderGrid(context, views, week, today, emptyColor, highlightColor)
      } else {
        renderEmpty(views, week, widgetData)
      }
      // 点击整个组件打开 App（只设一次，不给 35 个格子各设）
      // home_widget 0.10.0 的签名：getActivity(context, activityClass, uri)
      // —— 必须显式传 activityClass，没有只接受 context 的重载
      views.setOnClickPendingIntent(
          R.id.week_widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
      appWidgetManager.updateAppWidget(appWidgetId, views)
    }
  }

  /** 网格态：表头 7 列（今天列高亮）+ 5 行 × 7 格动态 addView。 */
  private fun renderGrid(
      context: Context,
      views: RemoteViews,
      week: WeekData,
      today: LocalDate,
      emptyColor: Int,
      highlightColor: Int,
  ) {
    views.setViewVisibility(R.id.week_header_row, View.VISIBLE)
    views.setViewVisibility(R.id.week_rows, View.VISIBLE)
    views.setViewVisibility(R.id.week_empty, View.GONE)

    views.setTextViewText(R.id.week_header_label, week.weekLabel)
    val dayNames = listOf("一", "二", "三", "四", "五", "六", "日")
    val headIds =
        listOf(
            R.id.week_head_mon,
            R.id.week_head_tue,
            R.id.week_head_wed,
            R.id.week_head_thu,
            R.id.week_head_fri,
            R.id.week_head_sat,
            R.id.week_head_sun)
    val todayIndex = today.dayOfWeek.value - 1 // 1=周一 → 0
    for (day in 0..6) {
      val date = week.dates.getOrNull(day) ?: ""
      views.setTextViewText(headIds[day], "${dayNames[day]}\n$date")
      // ★ 每格都必须显式设背景，不能只给"今天"设。
      // RemoteViews 是【增量应用】到已存在的 View 上的；表头这 7 个格子是
      // 布局里固有的 View，updateAppWidget 时不会被重建。若今天之外的分支
      // 什么都不做，昨天高亮的那格就会一直亮着，几天后满屏都是高亮。
      views.setInt(
          headIds[day],
          "setBackgroundColor",
          if (day == todayIndex) highlightColor else Color.TRANSPARENT,
      )
    }

    views.removeAllViews(R.id.week_rows)
    for (row in week.rows) {
      val rowRv = RemoteViews(context.packageName, R.layout.week_row)
      rowRv.setTextViewText(R.id.row_label, row.label)
      for (day in 0..6) {
        val cell = row.cells.getOrNull(day)
        val cellRv = RemoteViews(context.packageName, R.layout.week_cell)
        if (cell == null) {
          cellRv.setInt(R.id.cell_root, "setBackgroundColor", emptyColor)
        } else {
          cellRv.setTextViewText(R.id.cell_text, cell.text)
          cellRv.setInt(R.id.cell_root, "setBackgroundColor", cell.color)
          if (cell.extra > 0) {
            cellRv.setTextViewText(R.id.cell_extra, "+${cell.extra}")
            cellRv.setViewVisibility(R.id.cell_extra, View.VISIBLE)
          }
        }
        rowRv.addView(R.id.week_cells, cellRv)
      }
      views.addView(R.id.week_rows, rowRv)
    }
  }

  /**
   * 空状态（结构固定、内容左对齐）：
   * - 找到周但格子全空 → 表头照常 + 「本周没有课」；
   * - 找不到周（未配置 / 数据过期）→ 隐藏表头 + week_empty_text 兜底。
   */
  private fun renderEmpty(
      views: RemoteViews,
      week: WeekData?,
      widgetData: SharedPreferences,
  ) {
    if (week != null) {
      views.setViewVisibility(R.id.week_header_row, View.VISIBLE)
      views.setViewVisibility(R.id.week_rows, View.GONE)
      views.setViewVisibility(R.id.week_empty, View.VISIBLE)
      views.setTextViewText(R.id.week_header_label, week.weekLabel)
      views.setTextViewText(R.id.week_empty, "本周没有课")
    } else {
      views.setViewVisibility(R.id.week_header_row, View.GONE)
      views.setViewVisibility(R.id.week_rows, View.GONE)
      views.setViewVisibility(R.id.week_empty, View.VISIBLE)
      views.setTextViewText(
          R.id.week_empty,
          widgetData.getString(KEY_EMPTY_TEXT, null) ?: "打开 App 同步课表")
    }
  }

  private data class CellData(val text: String, val color: Int, val extra: Int)

  private data class RowData(val label: String, val cells: List<CellData?>)

  private data class WeekData(
      val weekStart: String,
      val weekLabel: String,
      val dates: List<String>,
      val rows: List<RowData>,
  ) {
    fun hasAnyCourse(): Boolean = rows.any { row -> row.cells.any { it != null } }
  }

  /** 解析 Dart 存的 `{"weeks": [...]}` JSON（防御式，绝不抛异常）。 */
  private fun parseWeeks(json: String?): List<WeekData> {
    if (json.isNullOrEmpty()) {
      return emptyList()
    }
    return runCatching {
      val weeks = JSONObject(json).optJSONArray("weeks") ?: return emptyList()
      (0 until weeks.length()).mapNotNull { weekIndex ->
        val week = weeks.optJSONObject(weekIndex) ?: return@mapNotNull null
        val rowsArray = week.optJSONArray("rows") ?: JSONArray()
        WeekData(
            weekStart = week.optString("weekStart"),
            weekLabel = week.optString("weekLabel"),
            dates = week.optJSONArray("dates")?.let { dates ->
              (0 until dates.length()).map { dates.optString(it) }
            } ?: emptyList(),
            rows =
                (0 until rowsArray.length()).mapNotNull { rowIndex ->
                  val row = rowsArray.optJSONObject(rowIndex) ?: return@mapNotNull null
                  val cells = row.optJSONArray("cells") ?: JSONArray()
                  RowData(
                      label = row.optString("label"),
                      cells =
                          (0 until cells.length()).map { cellIndex ->
                            val cell = cells.optJSONObject(cellIndex) ?: return@map null
                            CellData(
                                text = cell.optString("text"),
                                // Dart 的 ARGB int 是 64 位，可能超过 Kotlin Int.MAX；
                                // 必须 toLong 再 toInt，32 位 ARGB 位模式才正确
                                color =
                                    cell.optString("color").toLongOrNull()?.toInt() ?: 0,
                                extra = cell.optInt("extra"),
                            )
                          },
                  )
                },
        )
      }
    }.getOrDefault(emptyList())
  }

  private companion object {
    const val KEY_GRIDS = "week_grids"
    const val KEY_EMPTY_TEXT = "week_empty_text"
  }
}