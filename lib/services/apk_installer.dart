import 'package:flutter/services.dart';

/// 通过 MethodChannel 调 Kotlin 拉起 APK 安装器。
///
/// 未授权「安装未知应用」时 Kotlin 侧会拉起系统设置页并返回 false；
/// 任何平台异常都吞掉返回 false，不抛给 UI。
class ApkInstaller {
  ApkInstaller._();

  static const MethodChannel _channel = MethodChannel(
    'com.planeer.timetable/install',
  );

  /// 拉起安装器；返回 false 表示未完成（未授权 / 用户取消 / 出错）。
  static Future<bool> installApk(String path) async {
    try {
      return await _channel.invokeMethod<bool>('installApk', <String, dynamic>{
            'path': path,
          }) ??
          false;
    } catch (error) {
      return false;
    }
  }
}
