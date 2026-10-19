# 开发辅助脚本

`tools/` 下的脚本都不参与 App 运行时。

| 脚本 | 用途 |
|---|---|
| `release.ps1` | 一条命令构建可分发、签名正确的 release APK |
| `verify_jwxt_xls.dart` | 用真实教务 `.xls` 跑一遍导入管线，验证解析结果 |
| `gen_timetable_json.dart` | 把「按周展开」的教务 JSON 转成 App 的存储格式（测试/恢复数据用） |
| `gdust_crawl/` | 从教务系统抓课表，生成可直接导入的 `timetable.json` |

---

# 0. 抓取课表（`tools/gdust_crawl/`）

两套实现，都**不硬编码接口细节**（以免猜错），而是以你从浏览器里复制的
一条真实可用请求为准：

| 文件 | 说明 |
|---|---|
| **`启动.bat` + `gui.py`** | **推荐**。双击启动图形界面：填学号 + 复制 TOKEN 即可，学年学期总周数自动查 |
| `console_snippet.js` | 浏览器控制台版。不用装 Python、不用复制 Cookie |
| `crawl.py` | Python 版，纯标准库。适合脚本化 |
| `selftest.py` | `crawl.py` 的纯逻辑自测（不联网，62 项断言） |
| `TUTORIAL.md` | **分步使用教程**（先在 DevTools 里找请求，再跑脚本） |

⚠️ **没有在真实教务系统上验证过**——接口细节只有你自己能确认。
详细操作步骤见 [`gdust_crawl/README.md`](gdust_crawl/README.md)。

# 1. 发布 APK（`tools\release.ps1`）

一条命令生成可以直接发给同学安装的 APK（已签名、可分发）。

## 前置条件

只需要在新电脑上配置一次：

| 条件 | 怎么确认 |
|---|---|
| Flutter 已装且在 PATH | 终端里 `flutter --version` 有输出 |
| JDK 17 | 环境变量 `JAVA_HOME` 指向 JDK 目录（里面有 `bin\java.exe`） |
| Android SDK | 环境变量 `ANDROID_HOME`（或 `ANDROID_SDK_ROOT`）指向 SDK 目录 |
| 签名配置 | 项目里有 `android\key.properties` 文件 |

缺哪个，脚本都会用中文告诉你缺什么、该怎么改。

## 用法

在项目根目录打开 PowerShell：

```powershell
# 常规发布（构建 + 校验签名 + 输出）
.\tools\release.ps1

# 带发布说明（打印在摘要里，方便留档）
.\tools\release.ps1 -Notes "修复了小组件在深色模式下的显示问题"

# 已手动构建过，跳过构建直接用现有产物
.\tools\release.ps1 -SkipBuild
```

脚本会依次执行：解析版本号 → 前置检查 → `flutter build apk --release`
→ 签名校验 → 计算 SHA-256 → 复制到 `release\` 目录，最后打印发布摘要。

> 签名校验会拦截 debug 签名的包（提示「绝不能发出去」）。
> `-SkipVerify` 可以跳过校验，但正常情况不要用。

## 产物在哪

```
release\jiankebiao-<版本号>.apk
（例如 release\jiankebiao-1.3.0+5.apk）
```

把这个文件通过微信 / QQ / 网盘发给同学即可。

## 重要：安装前需先卸载旧版本

**debug 包与 release 包的签名不同，不能覆盖安装。**

如果手机上已经装过「用数据线连电脑调试装上去」的版本，直接安装
release 包会提示「应用未安装」，需要先把旧版本卸载掉。

## 重要：keystore 必须备份，丢了就发不了更新

release 签名用的密钥文件路径与密码，都记录在 `android\key.properties`
里（其中 `storeFile` 一行就是 keystore 文件的位置）。

**keystore 一旦丢失，就无法再给已安装的用户发更新**——换一个 keystore
签出来的包签名不同，老用户必须卸载重装。

备份建议：

- 把 keystore 文件和 `android\key.properties` 一起拷贝到 U 盘 / 私有网盘
- 这两个文件**不要**提交进 git，也**不要**发给别人

---

# 2. 验证教务 Excel 解析（`tools\verify_jwxt_xls.dart`）

不想在手机上试导入、只想确认解析对不对时用。

```powershell
dart run tools\verify_jwxt_xls.dart "E:\path\to\课表.xls"
```

输出：文件大小、工作表行数、解析出的课程数、学期名 / 第一周周一 / 总周数，
以及每门课的「星期、节次、周次、地点、教师、weekMask」。

**用它可以快速判断某个学校的导出文件能不能被正确解析。**

---

# 3. 教务 JSON 转 App 格式（`tools\gen_timetable_json.dart`）

把「按周展开」的教务 JSON 转成 App 的存储格式 `timetable.json`。
主要用于构造测试数据，或在数据被清空后从导出的 JSON 恢复。

```powershell
dart run tools\gen_timetable_json.dart <输入.json> <输出.json> [第一周周一]
```

例如：

```powershell
dart run tools\gen_timetable_json.dart in.json out.json 2026-08-31
```
