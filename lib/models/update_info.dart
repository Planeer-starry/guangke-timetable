/// version.json 契约模型（字段名不要改）。
class UpdateInfo {
  const UpdateInfo({
    required this.schema,
    required this.platform,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.sha256,
    required this.size,
    required this.releasedAt,
    required this.releaseNotes,
    required this.downloadUrl,
  });

  /// 契约版本号。
  final int schema;

  /// 平台标识。
  final String platform;

  /// 包名，必须与本 App 一致，不符则忽略（防止装错包）。
  final String packageName;

  /// 显示版本号，如 `1.0.1`。
  final String versionName;

  /// 递增版本号。
  final int versionCode;

  /// 最低支持的版本号，高于当前版本则强制更新。
  final int minSupportedVersionCode;

  /// APK 的 sha256（64 位十六进制）。
  final String sha256;

  /// APK 字节数。
  final int size;

  /// 发布时间（UTC ISO8601），解析失败为 null。
  final DateTime? releasedAt;

  /// 更新说明列表。
  final List<String> releaseNotes;

  /// APK 下载地址。
  final String downloadUrl;

  /// 防御式解析：字段缺失或类型不符回退默认值，绝不抛异常。
  ///
  /// 注意不能写 `as int?` / `as String?`——类型不符时 cast 本身会抛
  /// TypeError，必须用 `is` 判断后再取值。
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      schema: json['schema'] is int ? json['schema'] as int : 1,
      platform: json['platform'] is String
          ? json['platform'] as String
          : 'android',
      packageName: json['packageName'] is String
          ? json['packageName'] as String
          : '',
      versionName: json['versionName'] is String
          ? json['versionName'] as String
          : '',
      versionCode: json['versionCode'] is int ? json['versionCode'] as int : 0,
      minSupportedVersionCode: json['minSupportedVersionCode'] is int
          ? json['minSupportedVersionCode'] as int
          : 0,
      sha256: json['sha256'] is String ? json['sha256'] as String : '',
      size: json['size'] is int ? json['size'] as int : 0,
      releasedAt: json['releasedAt'] is String
          ? DateTime.tryParse(json['releasedAt'] as String)
          : null,
      releaseNotes: json['releaseNotes'] is List
          ? (json['releaseNotes'] as List).whereType<String>().toList()
          : <String>[],
      downloadUrl: json['downloadUrl'] is String
          ? json['downloadUrl'] as String
          : '',
    );
  }

  /// 版本号是否高于当前。
  bool isNewerThan(int currentVersionCode) => versionCode > currentVersionCode;

  /// 是否强制更新：服务器要求的最低版本高于当前版本。
  bool isForceUpdateFor(int currentVersionCode) =>
      minSupportedVersionCode > currentVersionCode;
}
