# 项目规约 · AGENTS.md

> ⛔ **本文件由人类维护。AI 助手禁止修改本文件。**
> 如果你（AI）认为本文件需要改动，请在回复里说明理由并**等我确认**，不要直接写入。
> 你的上下文里可能残留本文件的旧版本，**一律以磁盘上的当前内容为准**。

> 本文件是本仓库的**长期约定**，放在项目根目录。
> 每次开始新任务前先完整读一遍。有冲突时，本文件优先于你的默认习惯。

---

## 1. 项目是什么

一个 **Android 校园课表应用**，目标学校是 **广东科技学院**。核心功能三个：

1. 周课表查看（网格视图 + 当天课程）
2. 导入课表：**兼容广科 JSON 格式**，另外支持 Excel
3. 桌面小组件（「下节课」和「今日课程」）

### 明确不做（第一版）

- ❌ 校园地图、水电费查询、图书馆、成绩查询
- ❌ **App 内登录教务系统**（见下面第 4 节第 1 条，这是硬红线）
- ❌ iOS / Web / Windows 平台
- ❌ 账号体系、云同步、任何形式的用户数据上传

---

## 2. 技术栈（已定，不要替换、不要"优化"、不要多加库）

| 用途 | 选择 |
|---|---|
| 框架 | Flutter（stable channel） |
| **状态管理** | **不引入任何库**：`StatefulWidget` + `ValueNotifier` / `ValueListenableBuilder` |
| **本地存储** | `shared_preferences`（设置项）+ `path_provider`（课表 JSON 文件） |
| **路由** | **不引入库**：`Navigator` |
| 桌面小组件 | `home_widget` |
| 文件选择 | `file_picker` |
| Excel 解析 | `excel` |
| 日期格式化 | `intl` |
| 版本号（Phase 6） | `package_info_plus` |
| 开发依赖 | `flutter_lints`、`flutter_test` |

### 明确禁止引入的包

`drift`、`sqlite3_flutter_libs`、`sqflite`、`build_runner`、`flutter_riverpod`、`provider`、
`getx`、`go_router`、`dio`、`hive`、`isar`、`google_maps_flutter`、`flutter_map`、
**任何第三方课表 UI 组件**。

> 理由：这个 App 的数据量很小（一学期 20 周、几十门课），用 JSON 文件完全够，
> 引数据库会带来 build_runner 代码生成、原生 sqlite 依赖等一堆额外故障点。
> 需要新依赖**先问我**，不要自己加。

只构建 Android。**不要**运行 `flutter create` 添加其它平台。

---

## 3. 构建参数

- 包名：`com.planeer.timetable`（发布后不可更改）
- `compileSdk` / `targetSdk` / `minSdk`：**保持 `android/app/build.gradle.kts` 里现有的
  `flutter.compileSdkVersion` / `flutter.targetSdkVersion` / `flutter.minSdkVersion` 引用，
  不要改成写死的数字**
- 只保留 `android/` 平台目录
- 调试真机：OnePlus `OPD2506`，**Android 16 / API 36 / arm64**
- 应用显示名（`android:label`）：`简课表`（可改；**不要带"广科"** —— 应用已改为
  面向多校的通用课表工具，学校名只出现在数据与爬虫工具里）

> 本机已装：`platforms;android-35`、`platforms;android-36`、`build-tools;35.0.0/36.0.0`、
> `platform-tools`、`cmdline-tools;latest`。
> 如果构建仍提示缺某个 SDK 组件，**不要擅自改配置**，直接告诉我缺什么，
> 我来执行 `sdkmanager "xxx"`。

> ⚠️ **Gradle 发行包必须走国内镜像，不要改回去。**
> `android/gradle/wrapper/gradle-wrapper.properties` 里的 `distributionUrl` 已改为
> `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip`。
> 本机开着 Steam++ 加速器做 HTTPS 中间人，`services.gradle.org` 的重定向会被它劫持，
> Java 不信任其自签 CA，会报 `PKIX path building failed` 构建失败。
> **禁止**把 `distributionUrl` 改回 `services.gradle.org` 或 `downloads.gradle.org`。

---

## 4. 绝对规则（违反即视为错误）

1. **禁止以任何形式存储用户的账号密码。**
   本 App **不做教务系统登录**。课表通过「导入 JSON / 导入 Excel」获得，
   抓取由用户在电脑上跑外部脚本完成。`shared_preferences` 和 JSON 文件里
   **不得出现** `password`、`token`、`cookie`、`castgc` 这类字段。

2. **禁止联网上传**用户的课表、位置或任何个人信息。所有数据只存本机。
   第一版的所有功能都必须是**离线可用**的。

3. **禁止**一次性大重构。一次任务聚焦一个目标；预计改动超过 5 个文件时，
   先说明理由并等我确认。

4. **禁止**在 `pubspec.yaml` 里手写版本号。加依赖一律用 `flutter pub add <包名>`。
   不要臆造 API 或版本号。

5. **禁止**修改 `android/` 下 Flutter 自动生成的配置，**除非**任务明确是
   「桌面小组件」或「修改应用显示名（`android:label`）」。其它情况先问我。

6. **禁止**提交 `build/`、`.dart_tool/`、任何密钥文件或本地配置。

7. **禁止**用字符串（如 `"1-8,10"`）存储周次。见第 5 节的 `weekMask`。

8. **禁止执行任何删除/覆盖类命令**，包括但不限于
   `rm`、`del`、`Remove-Item`、`git clean`、`git checkout -- .`、`git reset --hard`、
   `flutter clean`、`rmdir`。
   需要清理任何东西时，**先告诉我，由我来执行**。

9. **你的工作范围严格限定在 `E:\dev\jiankebiao\projects\timetable` 目录内。**
   **禁止**读取、创建或修改该目录之外的任何文件——
   尤其是 `C:\Users\...\.codeartsdoer\`、用户主目录、其它盘符。
   如果某个操作需要超出这个范围，**停下来问我**。

10. **禁止修改本文件（AGENTS.md）。** 见文件顶部声明。

11. **`flutter analyze` / `flutter test` / `flutter run` 由人类执行，你不要尝试运行。**

    ⚠️ 这几条命令会让 Flutter 以**管道 stdio** 启动子进程（`dart.exe`），
    而你的沙箱禁止管道 → 命令会**永久挂起、零输出**，看起来像 Flutter 卡了。
    已实测对比：

    | 命令 | 结果 |
    |---|---|
    | `dart.exe format .` | ✅ 能跑（不启子进程） |
    | `flutter analyze` | ❌ 挂死，输出文件 0 字节 |
    | `flutter --version` / `flutter.bat analyze` | ❌ 同上 |

    **正确分工：**

    - 你负责**写代码** + 用 `dart.exe format .` 格式化
    - 写完在回复末尾给出这两条命令，**交给我在 PowerShell 里执行**：

      ```
      flutter --no-version-check analyze
      flutter --no-version-check test
      ```

    - **等我把原始输出贴回来**，再根据真实结果判断是否通过、下一步做什么
    - 🚫 **禁止**声称「已完成」「测试通过」「analyze 无 issue」——
      你没有能力验证这些，编造或推测结果是最严重的违规

12. **其它 Dart 命令：绕开 POSIX shell 脚本，且必须前台执行。**

    `flutter` / `dart`（不带后缀）是 **POSIX shell 脚本**，内部用 `$(...)`
    命令替换，在你的 bash 沙箱里会报
    `cannot make pipe for command substitution: Permission denied` 并卡死。
    需要用 Dart 工具时，调 `.exe`：

    ```bash
    E:/dev/jiankebiao/flutter/bin/dart.exe format .
    ```

    另外：

    - **禁止** `nohup` / `&` / `disown` 把命令丢后台，再用 `sleep` + `cat` 猜结果
    - 输出可能很长时重定向到文件再读（`... > build/out.txt 2>&1`），不要接 `head`
    - 任何命令超过 **3 分钟**无输出：**立刻停下来告诉我**，
      不要反复重试，也不要换着花样试——把错误原文贴出来比多试十次有用

---

## 5. 数据模型

### 5.1 存储位置与「单一真源」原则

课表数据存成一个 JSON 文件：

```
<getApplicationDocumentsDirectory()>/timetable.json
```

**学期参数（`school` / `semesterName` / `week1Monday` / `totalWeeks`）的唯一真源是
`timetable.json` 里的 `meta`，禁止在 `shared_preferences` 里另存一份。**

`shared_preferences` 只允许存 **UI 偏好**，例如：

- 当前查看的周次（只是"临时浏览位置"，不是学期参数）
- 主题模式（跟随系统 / 亮 / 暗）
- 上次导入时间、来源文件名的展示用缓存
- 是否已展示过某个引导

> 理由：学期参数与课表数据强绑定。分开存会在换学期时出现「课表已换、周次没换」
> 这类不一致。**同一份信息只允许有一个写入点。**

另外，`StorageService` 的目录**必须能从构造函数注入**（`Directory` 参数），
以便单元测试改用临时目录；同时提供一个便利工厂
`StorageService.forApp()`，内部调用 `path_provider` 取真实目录。
**禁止**在 service 内部直接调 `getApplicationDocumentsDirectory()`，
否则测试无法运行。

### 5.2 JSON 结构（对外契约，不要改动字段名）

```json
{
  "schema": 1,
  "meta": {
    "school": "广东科技学院",
    "semesterName": "2026-2027 第一学期",
    "week1Monday": "2026-09-07",
    "totalWeeks": 20
  },
  "periods": [
    { "index": 1,  "start": "08:30", "end": "09:15" },
    { "index": 2,  "start": "09:20", "end": "10:05" },
    { "index": 3,  "start": "10:25", "end": "11:10" },
    { "index": 4,  "start": "11:15", "end": "12:00" },
    { "index": 5,  "start": "14:40", "end": "15:25" },
    { "index": 6,  "start": "15:30", "end": "16:15" },
    { "index": 7,  "start": "16:30", "end": "17:15" },
    { "index": 8,  "start": "17:20", "end": "18:05" },
    { "index": 9,  "start": "19:30", "end": "20:15" },
    { "index": 10, "start": "20:20", "end": "21:05" }
  ],
  "courses": [
    {
      "id": "c_001",
      "name": "计算机网络",
      "teacher": "张三",
      "location": "教学楼A101",
      "colorValue": 4294198070,
      "dayWeek": 1,
      "sectionStart": 3,
      "sectionEnd": 4,
      "weekMask": 65535,
      "note": ""
    }
  ],
  "overrides": [
    {
      "courseId": "c_001", "week": 8,
      "dayWeek": 3, "sectionStart": 5, "sectionEnd": 6,
      "location": "实验楼B203"
    }
  ]
}
```

- `dayWeek`：1=周一 … 7=周日
- `sectionStart` / `sectionEnd`：节次序号，闭区间（连堂课是 3~4）
- `periods` 上面的值就是**广科真实作息**，直接作为默认值写进代码，不要自己编
- `colorValue`：ARGB int，为空时按课程名哈希稳定取色

### 5.3 weekMask 语义（最重要，写错等于全盘皆错）

- 32 位整数。**第 n 周有课 ⇔ 第 `(n-1)` 位为 1**，即 `1 << (n - 1)`
- 必须写成独立、可单测的纯函数（放 `lib/utils/week_mask.dart`，**不依赖 flutter**）：

```dart
bool hasClassInWeek(int weekMask, int week);      // week 从 1 开始
int weekMaskFromWeeks(Iterable<int> weeks);
List<int> weeksFromWeekMask(int weekMask);
```

- 禁止用 `"1-8,10"` 这类字符串存周次。**字符串解析只允许出现在导入阶段**，
  解析完立刻转成 mask 存文件。

### 5.4 导入：广科 JSON（Phase 4 的核心）

外部 Python 脚本（用户自己在电脑上跑）导出的 `timetable.json` 是**按周展开**的格式：

```json
{
  "1": [ { "courseName": "计算机网络", "teacher": "张三",
           "classroomName": "教学楼A101", "whichSection": 3,
           "dayWeek": 1, "week": 1, "courseDate": "" } ],
  "2": [ ... ],  ...  "20": [ ... ]
}
```

字段别名要**全部兼容**（同一个字段可能有多种写法）：

| 内部字段 | 兼容的 JSON 键 |
|---|---|
| `name` | `courseName`, `kcmc`, `name` |
| `teacher` | `teacher`, `teacherName`, `xm` |
| `location` | `classroomName`, `classroom`, `room`, `jxdd` |
| `sectionStart` | `whichSection`, `jcs`, `section`（取其中第一个数字） |
| `dayWeek` | `dayWeek`, `xqj` |

**导入时必须做两级聚合**，顺序不能颠倒：

1. **第一级 —— 合并连堂**：在**同一周内**，若同一
   `(name, teacher, location, dayWeek)` 出现在**连续**的节次上
   （如 3 和 4），合并成一条 `sectionStart=3, sectionEnd=4`。
2. **第二级 —— 合并周次**：把所有周里
   `(name, teacher, location, dayWeek, sectionStart, sectionEnd)` 完全相同的记录
   归为同一门课，出现的所有周次 → 计算成一个 `weekMask`。

聚合逻辑必须是**纯函数**（输入解析后的原始条目，输出 `List<Course>`），
放 `lib/utils/` 下，并写单元测试。

### 5.5 必须有的单元测试

`test/week_mask_test.dart`：

- 空集合 → mask 为 0
- 第 1 周（`1`）、第 20 周（`1 << 19`）、第 32 周（边界）
- mask ↔ weeks 往返一致
- 第 0 周、第 33 周要安全处理，不能抛异常

`test/import_test.dart`：

- 单周单次课 → 1 条课程，mask 只有 1 位
- 同一门课出现在 1~16 周 → 1 条课程，mask = `0xFFFF`
- 连堂 3-4 节 → 1 条课程，`sectionStart=3, sectionEnd=4`
- 不连续节次（3 和 5）**不能**被合并
- 字段别名（`kcmc` / `jcs` / `jxdd`）能正确解析
- **跨学期隔离**：导入新学期数据时旧数据要被替换，不能混在一起

### 5.6 查询要求

- 取某周课表：`courses.where((c) => hasClassInWeek(c.weekMask, week))` 再按
  `overrides` 应用当周调整。数据量小，在内存里过滤是可以的。
- 计算「今天是第几周」：由 `meta.week1Monday` 推：
  `((today - week1Monday).inDays ~/ 7 + 1)`，并 clamp 到 `1..totalWeeks`。
  **必须写成纯函数并加单测**，注意时区和「周一为一周第一天」。

---

## 6. 学校背景（广东科技学院，供你理解需求，不要写进 App）

以下是已知事实，**仅供你理解数据来源**，App 本身不访问这些：

```
教务系统        http://172.16.254.1          （校园内网，外网已关闭）
CAS 统一认证    https://cas.gdust.edu.cn/cas-api
WebVPN          https://webvpn.gdust.edu.cn  （校外访问用）
智慧校园门户    https://portal.gdust.edu.cn
课表接口        {门户}/smart-admin-api/app/zf/get_student_course
                ?jobNumber={学号}&year={年}&semester={12|03}&week={周}

学期参数：12 = 第一学期，03 = 第二学期
作息时间：共 10 节，见 5.2 节的 periods
```

课表数据由用户**在电脑上**用外部脚本抓取成 JSON，再传到手机导入。
参考实现：`https://github.com/chenzhuoxi/GDUST_timetable`（Python，**无许可证，只可读思路不可抄代码**）。
另一参考：`https://github.com/chenzhuoxi/GDUST_timetable_lite`（Flutter，**MIT 许可，可参考甚至复用**）。

---

## 7. 工作方式（每个任务都按这个循环）

1. 先用一两句话**复述**你对任务的理解
2. 列出你打算**创建/修改哪些文件**
3. 写代码
4. 运行 `dart format .` 和 `flutter analyze`，**把原始输出贴出来**
5. 运行相关单元测试，贴上结果
6. 最后输出四段：
   - **改了什么**
   - **怎么验证的（命令 + 结果）**
   - **没解决的 / 不确定的**
   - **需要我手动做的事**

**不要跳过第 4、5 步。** 如果 `flutter analyze` 有 error，先修完再汇报，
不要带着 error 说「完成了」。

---

## 8. 你做不到的事，要说出来

你无法安装 Flutter / Android SDK、无法连接手机、无法点按 App 界面。
遇到这类事，**直接告诉我需要执行的命令和期望输出**，
不要假装完成了，也不要编造运行结果。

---

## 9. 代码风格

- 注释、提交信息、UI 文案全部用**中文**
- 用 `const` 构造函数，遵守 `flutter_lints`
- widget 拆小，单文件超过 300 行就考虑拆分
- 业务逻辑放 `lib/services/` 或 `lib/utils/`，不要写进 widget 的 `build` 方法
- 文件命名用 snake_case
- 纯逻辑（周次计算、导入解析、颜色生成）**必须**能脱离 Flutter 单测
