import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:timetable/constants/app_config.dart';
import 'package:timetable/models/update_info.dart';

/// 应用内更新：检查、下载、校验。
///
/// 检查失败（断网 / 超时 / JSON 错）一律返回 null，**绝不抛异常、绝不影响使用**。
class UpdateService {
  UpdateService._();

  static const Duration _timeout = Duration(seconds: 10);

  /// 会话内缓存：距上次检查不足该时长则直接复用结果。
  static const Duration _cacheTtl = Duration(minutes: 10);
  static DateTime? _lastCheckAt;
  static UpdateInfo? _lastResult;

  /// 拉取服务器 version.json（含 10 分钟会话缓存）。
  ///
  /// [useMockUpdate] 为 true（调试开关）时返回伪造的新版本，不请求网络。
  /// 网络失败 / 超时 / HTTP 非 200 / JSON 无法解析都会**抛异常**，
  /// 由调用方决定怎么提示（设置页主动检查需要区分「失败」和「无更新」）。
  static Future<UpdateInfo> fetchUpdateInfo({bool forceRefresh = false}) async {
    if (useMockUpdate) {
      return _mockInfo();
    }
    final DateTime now = DateTime.now();
    if (!forceRefresh) {
      final UpdateInfo? cached = _lastResult;
      final DateTime? checkedAt = _lastCheckAt;
      if (cached != null &&
          checkedAt != null &&
          now.difference(checkedAt) < _cacheTtl) {
        return cached;
      }
    }
    final http.Response response = await http
        .get(Uri.parse(updateInfoUrl))
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('version.json 顶层不是 JSON 对象');
    }
    final UpdateInfo info = UpdateInfo.fromJson(decoded);
    _lastCheckAt = now;
    _lastResult = info;
    return info;
  }

  /// 静默检查更新（首页启动时用）。
  ///
  /// 任何失败一律返回 null，**绝不抛异常、绝不影响使用**。
  static Future<UpdateInfo?> checkForUpdate({
    required int currentVersionCode,
    required String packageName,
  }) async {
    try {
      final UpdateInfo info = await fetchUpdateInfo();
      return evaluateUpdate(info, currentVersionCode, packageName);
    } catch (error) {
      return null;
    }
  }

  /// 纯函数：判定某个 version.json 结果是否构成可用更新。
  ///
  /// packageName 不符（防装错包）或 versionCode 不高于当前 → null。
  static UpdateInfo? evaluateUpdate(
    UpdateInfo info,
    int currentVersionCode,
    String packageName,
  ) {
    if (info.packageName != packageName) {
      return null;
    }
    if (!info.isNewerThan(currentVersionCode)) {
      return null;
    }
    return info;
  }

  /// 流式下载 APK 到 `<临时目录>/apk/app-release.apk`。
  ///
  /// 修正 A2：用 `sha256.startChunkedConversion()` 在下载过程中**边收边算**，
  /// 下载结束直接拿 digest，不在内存里读整个 APK（低端机不 OOM）。
  /// sha256 不符 → 删除坏文件并抛出，绝不留下损坏的 APK。
  /// [onProgress] 回调 0..1 的进度。
  static Future<File> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final Directory dir = Directory(
      '${(await getTemporaryDirectory()).path}/apk',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final File file = File('${dir.path}/app-release.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final http.Client client = http.Client();
    final IOSink sink = file.openWrite();
    final _DigestSink digestSink = _DigestSink();
    final ByteConversionSink hashSink = sha256.startChunkedConversion(
      digestSink,
    );
    try {
      final http.StreamedResponse response = await client.send(
        http.Request('GET', Uri.parse(info.downloadUrl)),
      );
      if (response.statusCode != 200) {
        throw StateError('下载失败：HTTP ${response.statusCode}');
      }
      final int total = response.contentLength ?? info.size;
      int received = 0;
      await for (final List<int> chunk in response.stream) {
        hashSink.add(chunk);
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      hashSink.close();
      final String actual = digestSink.value.toString();
      if (actual != info.sha256.toLowerCase()) {
        if (await file.exists()) {
          await file.delete();
        }
        throw StateError('文件校验失败（sha256 不符），已删除损坏的下载文件');
      }
      onProgress?.call(1.0);
      return file;
    } catch (error) {
      await sink.close();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// 调试用：伪造的新版本（useMockUpdate = true 时返回）。
  static UpdateInfo _mockInfo() {
    return UpdateInfo(
      schema: 1,
      platform: 'android',
      packageName: 'com.planeer.timetable',
      versionName: '1.0.1',
      versionCode: 2,
      minSupportedVersionCode: 1,
      sha256: '0',
      size: 1,
      releasedAt: null,
      releaseNotes: <String>['调试用：mock 新版本'],
      downloadUrl: 'https://example.com/app-release.apk',
    );
  }
}

/// 收集 `sha256.startChunkedConversion` 产出的 digest。
///
/// 注意：`package:crypto` **没有** `AccumulatorSink` 这个类
/// （`crypto.dart` 只导出 digest / hash / hmac / md5 / sha1 / sha256 / sha512，
/// `src/digest_sink.dart` 里也没有它），所以这里自己实现一个最简的
/// `Sink<Digest>`。这样就能边下载边算哈希，不需要把 54MB 的 APK
/// 一次性读进内存（低端机不会 OOM）。
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
