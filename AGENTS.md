# 项目规约 · AGENTS.md

> 本文件是本仓库的**长期约定**，放在项目根目录。
> 每次开始新任务前先完整读一遍。有冲突时，本文件优先于你的默认习惯。

---

## 1. 项目是什么

一个 **Android 校园课表应用**。核心功能只有两个：

1. 周课表查看 + 从 Excel 导入
2. 桌面小组件（「下节课」和「完整周课表」）

**第一版明确不做**：校园地图、水电费查询、教务系统自动登录、iOS、账号体系、云同步。

### 技术栈（已定，不要替换、不要"优化"）

| 用途 | 选择 |
|---|---|
| 框架 | Flutter（stable channel） |
| 状态管理 | flutter_riverpod |
| 本地数据库 | drift + drift_flutter + sqlite3_flutter_libs |
| 代码生成 | drift_dev + build_runner |
| 路由 | go_router |
| 桌面小组件 | home_widget |
| 文件选择 / 解析 | file_picker + excel |
| 其他 | intl / path_provider / package_info_plus / http / crypto / uuid |

只构建 Android。**不要**运行 `flutter create` 添加 iOS、Web、Windows 平台。

---

## 2. 构建参数

- 包名：`com.planeer.timetable`（发布后不可更改）
- `compileSdk` / `targetSdk` / `minSdk`：**保持 `android/app/build.gradle.kts` 里现有的
  `flutter.compileSdkVersion` / `flutter.targetSdkVersion` / `flutter.minSdkVersion` 引用，
  不要改成写死的数字**
- 只保留 `android/` 平台目录
- 调试真机：OnePlus `OPD2506`，**Android 16 / API 36 / arm64**

> 本机已装：`platforms;android-35`、`platforms;android-36`、`build-tools;35.0.0/36.0.0`、
> `platform-tools`、`cmdline-tools;latest`。
> 如果构建仍提示缺某个 SDK 组件，**不要擅自改配置**，直接告诉我缺什么，
> 我来执行 `sdkmanager "xxx"`。

---

## 3. 绝对规则（违反即视为错误）

1. **禁止**以任何形式存储用户的账号密码。第一版完全接触不到教务系统登录，只做本地 Excel 导入。
2. **禁止**联网上传用户的课表、成绩、位置或任何个人信息。所有业务数据只存本机。
3. **禁止**引入这些包：任何第三方课表 UI 组件、`google_maps_flutter`、`flutter_map`、
   `dio`、`getx`、`hive`、`provider`(旧版)。需要新依赖先问我。
4. **禁止**一次性大重构。一次任务聚焦一个目标；预计改动超过 5 个文件时，先说明理由并等我确认。
5. **禁止**在 `pubspec.yaml` 里手写版本号。加依赖一律用
   `flutter pub add <包名>`，让 pub 自己解析兼容版本。不要臆造 API 或版本号。
6. **禁止**修改 `android/` 下 Flutter 自动生成的配置，**除非**任务明确是"桌面小组件"。
7. **禁止**提交 `build/`、`.dart_tool/`、`*.g.dart` 之外的生成物或任何密钥文件。

---

## 4. 数据模型（必须严格按此实现，不得自行更改语义）

用 drift 建这四张表：

```
Semester  学期
  id          自增主键
  name        "2025-2026 第一学期"
  startDate   第 1 周的周一（DateTime，只用日期部分）
  totalWeeks  总周数，默认 20

Period  节次
  id          自增主键
  name        "第1节"
  startTime   "08:00"
  endTime     "08:45"
  sortOrder   排序用整数

Course  课程（一条记录 = 一门课在某个时间段的一次安排）
  id           自增主键
  semesterId   外键 → Semester.id
  name         课程名
  teacher      教师（可空）
  location     地点（可空）
  colorValue   颜色 int（可空，为空时按课程名哈希取色）
  weekday      1=周一 … 7=周日
  periodStart  起始节次（引用 Period.sortOrder）
  periodEnd    结束节次
  weekMask     32 位整数位掩码，见下
  note         备注（可空）

CourseOverride  调课（某周临时改时间/地点）
  id, courseId, week, newWeekday, newPeriodStart, newPeriodEnd, newLocation
```

### weekMask 语义（最重要，写错等于全盘皆错）

- 32 位整数。**第 n 周有课 ⇔ 第 (n-1) 位为 1**（即 `1 << (n - 1)`）。
- 必须提供并写成独立、可单测的纯函数：

```dart
bool hasClassInWeek(int weekMask, int week);      // week 从 1 开始
int weekMaskFromWeeks(Iterable<int> weeks);
List<int> weeksFromWeekMask(int weekMask);
```

- **禁止**用 `"1-8,10"` 这类字符串存储周次。解析只允许出现在「导入」这一步，
  解析完立刻转成 mask 存库。

### 查询要求

- 查某学期的某周课表，必须用 SQL 层过滤（`where` + 位运算），
  **禁止**把整表取出来再在 Dart 里 filter。
- 所有查询必须带 `semesterId` 条件。
- 必须实现「同一天同一节次冲突检测」方法。

### 必须有的单元测试

`test/week_mask_test.dart`，至少覆盖：

- 空集合 → mask 为 0
- 第 1 周、第 32 周（边界）
- "1-8"、"单周"、"双周"、"1-8,10,12-16" 的解析
- mask ↔ weeks 往返一致
- 跨学期隔离（semesterId 过滤正确）

---

## 5. 工作方式（每个任务都按这个循环）

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
不要带着 error 说"完成了"。

---

## 6. 你做不到的事，要说出来

你无法安装 Flutter SDK / Android SDK、无法连接手机、无法点按 App 界面。
遇到这类事，**直接告诉我需要执行的命令和期望输出**，不要假装完成了，也不要编造运行结果。

---

## 7. 代码风格

- 注释、提交信息、UI 文案全部用**中文**
- 用 `const` 构造函数，遵守 `flutter_lints`
- widget 拆小，单文件超过 300 行就考虑拆分
- 业务逻辑放 `providers/` 或 `data/`，不要写进 widget 的 build 方法
- 文件命名用 snake_case
