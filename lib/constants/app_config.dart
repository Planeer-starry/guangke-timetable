/// 全局配置常量。
///
/// updateInfoUrl 是 version.json 的地址（占位，换成实际服务器地址）。
const String updateInfoUrl = 'https://example.com/version.json';

/// 调试开关：true 时检查更新返回伪造的新版本、不请求网络，
/// 用于在没有服务器的情况下先把 UI 流程跑通。
const bool useMockUpdate = false;
