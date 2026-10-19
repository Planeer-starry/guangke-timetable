package com.planeer.timetable

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.ContextCompat

/**
 * 小组件共享颜色工具（J6 主题包）。
 *
 * 技术边界（如实告知用户）：卡片背景色与文字色【不】跟随主题包——
 * RemoteViews 无法设置程序化创建的圆角 Drawable（改纯色会丢失圆角），
 * 文字跟着变有对比度风险。只有强调色（今日列高亮 / 下节课色条）与
 * 课程色（Dart 算好经 JSON 传入）跟随主题包。
 */
object WidgetColors {

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
}