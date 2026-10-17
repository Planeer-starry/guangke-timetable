package com.planeer.timetable

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/**
 * APK 安装辅助（Dart 侧经 MainActivity 的 MethodChannel 调进来）。
 *
 * 返回 true 仅表示「成功拉起系统安装器」，用户装没装完由系统界面决定。
 * Android 8+ 未授予「安装未知应用」时，跳系统授权页并返回 false，
 * 由 Dart 侧提示用户授权后重试。
 */
object ApkInstaller {

  /** 拉起系统安装器；false = 未完成（文件不存在 / 未授权 / 拉起失败）。 */
  fun installApk(context: Context, path: String): Boolean {
    val file = File(path)
    if (!file.exists()) {
      return false
    }

    // Android 8 起必须先拿到「安装未知应用」授权（按应用粒度）
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        !context.packageManager.canRequestPackageInstalls()) {
      val intent =
          Intent(
              Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
              Uri.parse("package:${context.packageName}"))
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
      return false
    }

    return try {
      val uri =
          FileProvider.getUriForFile(
              context, "${context.packageName}.fileprovider", file)
      val intent = Intent(Intent.ACTION_VIEW)
      intent.setDataAndType(uri, "application/vnd.android.package-archive")
      intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
      true
    } catch (error: Exception) {
      false
    }
  }
}