/// 全局配置常量。
library;

/// `version.json` 的地址。
///
/// **留空 = 关闭应用内更新功能**：
///   - 设置页不显示「检查更新」这一组
///   - App 启动时不会发起静默检查
///   - 首页也不会出现「发现新版本」提示条
///
/// 将来想启用，把托管地址填进来即可。**不需要自己有网站**：
///   - GitHub Releases 的附件直链
///   - Cloudflare R2 / Pages 的公开 https 地址
///   - 任何能返回 version.json 的 https 地址
///
/// 留空时本 App 完全离线，不会发起任何网络请求。
const String updateInfoUrl = '';

/// 调试开关：true 时检查更新返回伪造的新版本、不请求网络，
/// 用于在没有服务器的情况下先把更新 UI 流程跑通。
/// （仅在 [updateInfoUrl] 为空时才有意义，方便本地验证界面。）
const bool useMockUpdate = false;

/// 应用内更新是否启用。
///
/// `updateInfoUrl` 为空且没开 mock 时为 `false` —— 此时所有更新相关入口隐藏。
bool get isUpdateEnabled => useMockUpdate || updateInfoUrl.isNotEmpty;
