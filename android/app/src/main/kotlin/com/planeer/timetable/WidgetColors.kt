package com.planeer.timetable

import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.os.Build
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import org.json.JSONObject

/**
 * 小组件共享颜色工具（J6 强调色 / J9 皮肤）。
 *
 * J9 起卡片背景 / 文字 / 分隔线 / 淡底跟随主题包：Dart 侧
 * `widgetSkinFromTheme` 算好亮暗两套，经 home_widget 写入 `widget_skin`，
 * 这里按系统深色模式挑一套（[skinOf]）。Android 12+ 经
 * backgroundTintList 给现有圆角 shape 换色（tint 模式 SRC_IN 保圆角），
 * 12 以下只有文字色跟随；未设置 / 解析失败时全部回退 res 资源
 * （values / values-night 自动切换），行为与 J8 及之前完全一致。
 */
object WidgetColors {

  /** 一套小组件皮肤（六个 ARGB 色，[skinOf] 解析）。 */
  data class Skin(
      val card: Int,
      val title: Int,
      val sub: Int,
      val divider: Int,
      val gridEmpty: Int,
      val accent: Int,
  )

  /**
   * 当前小组件强调色：Dart 侧主题包经 home_widget 写入的 `widget_accent`
   * （ARGB int 的十进制字符串，与课程色同套路——Dart int 是 64 位，
   * 可能超过 Kotlin Int.MAX，必须 toLong 再 toInt 还原 32 位位模式）。
   * 缺失 / 无法解析时回退 res 资源色（values / values-night 自动切换）。
   */
  fun accentOf(widgetData: SharedPreferences, context: Context): Int {
    val raw = widgetData.getString("widget_accent", null)
    return raw?.toLongOrNull()?.toInt()
        ?: ContextCompat.getColor(context, R.color.widget_accent)
  }

  /** 系统是否深色模式（皮肤挑套用）。 */
  fun isNightMode(context: Context): Boolean {
    val uiMode = context.resources.configuration.uiMode
    return uiMode and Configuration.UI_MODE_NIGHT_MASK ==
        Configuration.UI_MODE_NIGHT_YES
  }

  /**
   * 当前皮肤：读 `widget_skin`
   * （`{"light":{…},"dark":{…},"mode":"system"|"light"|"dark"}`）。
   *
   * 亮暗套的选择规则（对应 Dart 的 `widgetSkinPayload`）：
   * - `mode = "light"` / `"dark"`：用户在 App 里强制指定了主题 ——
   *   **必须照办**。若这里只看系统深浅色，会出现「App 深色、小组件亮色」，
   *   也就是用户报的「小组件不跟随主题」。
   * - `mode = "system"` 或缺失：每次渲染时**现读** `uiMode`。
   *   不能下发一个固定亮度值 —— App 没运行时系统切了主题会挑到陈旧的那套。
   *
   * 全 try/catch + 字段级兜底：任何缺失 / 非法都整体返回 null，
   * 调用方回退资源色——绝不渲染「半套皮肤」。
   */
  fun skinOf(widgetData: SharedPreferences, context: Context): Skin? {
    val raw = widgetData.getString("widget_skin", null)
    if (raw.isNullOrEmpty()) {
      return null
    }
    return try {
      val root = JSONObject(raw)
      val mode = root.optString("mode", "")
      val key = when (mode) {
        "dark" -> "dark"
        "light" -> "light"
        else -> if (isNightMode(context)) "dark" else "light"
      }
      val skin = root.optJSONObject(key) ?: return null
      // 局部函数返回 Int? ，逐个 `?: return null` 让任一字段缺失就整体失败。
      //
      // ⚠️ 不能写成 `fun colorOf(name: String): Int = ... ?: return null`：
      // Kotlin 不允许非空 Int 返回类型的函数 return null，会直接编译失败
      // （e: Null cannot be a value of a non-null type 'Int'，J9 构建时踩到）。
      fun colorOf(name: String): Int? =
          skin.optString(name).toLongOrNull()?.toInt()

      val card = colorOf("card") ?: return null
      val title = colorOf("title") ?: return null
      val sub = colorOf("sub") ?: return null
      val divider = colorOf("divider") ?: return null
      val gridEmpty = colorOf("gridEmpty") ?: return null
      // 强调色缺失时回退资源色，与 J6 的 accentOf 行为一致
      val accent =
          colorOf("accent") ?: ContextCompat.getColor(context, R.color.widget_accent)
      Skin(
          card = card,
          title = title,
          sub = sub,
          divider = divider,
          gridEmpty = gridEmpty,
          accent = accent)
    } catch (e: Exception) {
      null
    }
  }

  /**
   * 给根布局的圆角卡片背景换色（Android 12+）：RemoteViews.setColorStateList
   * 调 View.setBackgroundTintList，tint 模式 SRC_IN——只换色、保留圆角。
   * 12 以下跳过（该方法 API 31 才有），卡片保持资源底色。
   */
  fun applyCardTint(views: RemoteViews, viewId: Int, color: Int) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      views.setColorStateList(
          viewId, "setBackgroundTintList", ColorStateList.valueOf(color))
    }
  }
}