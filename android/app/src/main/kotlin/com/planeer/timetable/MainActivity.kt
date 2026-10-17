package com.planeer.timetable

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  private companion object {
    const val CHANNEL = "com.planeer.timetable/install"
  }

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "installApk" -> {
              val path = call.argument<String>("path")
              if (path == null) {
                result.error("-1", "installApk 需要 path 参数", null)
                return@setMethodCallHandler
              }
              result.success(ApkInstaller.installApk(this, path))
            }
            else -> result.notImplemented()
          }
        }
  }
}
