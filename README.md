# 简课表

一款 Android 课表应用。Flutter 编写，**单机离线**，数据全部存在本机。

> 为「教务系统只能网页看课表」这个痛点做的。导入一次，之后开 App 或看桌面小组件就行。

**下载**：[Releases](https://github.com/Planeer-starry/guangke-timetable/releases) 里下载最新 `.apk` 安装即可。

---

## 目录

- [功能](#功能)
- [课表抓取工具](#课表抓取工具)
- [技术栈](#技术栈)
- [隐私](#隐私)
- [构建](#构建)
- [项目结构](#项目结构)
- [适配你的学校](#适配你的学校)
- [已知限制](#已知限制)

---

## 功能

### 课表

- 周视图网格，连堂自动合并、单双周区分、今天列高亮
- **左右滑动换周**，边缘回弹；「回到本周」按需显示
- 深色模式；平板 / 手机自适应（<600 / 600–840 / ≥840dp 三档断点）
- 时间列显示每节课的起止时间

### 导入

- **教务系统 Excel 导入**（`.xls` / `.xlsx`）：自动识别学期名、第一周周一、总周数、
  节次与周次；表头两级识别、星期列映射、节次行推断，尽量兼容不同学校的表格样式
- **JSON 导入**（文件或剪贴板）：App 导出的格式，或下面「课表抓取工具」生成的文件
- **导入预览**：识别到的课程数、学期信息、作息来源、被跳过的条目

### 外观

三个维度互相独立，都可自定义：

| 维度 | 内置 | 可导入 |
|---|---|---|
| **主题** | 跟随系统 / 浅色 / 深色 | — |
| **主题包** | 靛蓝 · 墨绿 · 绛红 · 琥珀 · 石板 · 紫罗兰 | ✅ `.json` |
| **课程配色** | 默认（16 色）· 莫兰迪（12 色）· 秋日（12 色） | ✅ `.json` |

主题包决定界面主色，Material 3 会据此派生整套配色；
课程配色决定课块颜色，**不跟随主题包**（两者正交，可自由组合）。

面板里每行有「⋯」菜单：重命名 / 复制 JSON / 删除（内置包只读，可复制 JSON 当起点）。

<details>
<summary>主题包 JSON 格式</summary>

```json
{
  "schema": 1,
  "id": "midnight",
  "name": "午夜",
  "seedColor": "#4F5AA8",
  "coursePalette": ["#B5473E", "#3E6FA8", "#2F7D5B", "#A8792C"],
  "widgetAccent": "#4F5AA8"
}
```

- `seedColor` 必填，`#RRGGBB` 或 `#AARRGGBB`
- `coursePalette` 可选，8~24 个颜色；带上它会同时切换课程配色
- `widgetAccent` 可选，默认取 `seedColor`

</details>

<details>
<summary>课程配色 JSON 格式</summary>

```json
{
  "schema": 1,
  "id": "morandi",
  "name": "莫兰迪",
  "colors": ["#8C6A5D", "#6F8065", "#64788A", "#8A6A7A"]
}
```

也接受裸数组快捷写法：`["#8C6A5D", "#6F8065", "#64788A"]`

颜色数量需 8~24；内置配色全部满足白字对比度 ≥ 3.5:1（实测 4.16 ~ 6.94）。

</details>

### 作息时间

不同学校作息不同，所以节次时间和数量都可改：

- 设置 → 学期 → 作息时间：逐节修改起止时间
- 自定义时间面板（时 / 分双轮盘 + 常用时间快捷）
- 添加一节 / 删除最后一节 / 整体平移（如全部提前 10 分钟）/ 恢复默认
- 改完以后**周视图时间列、课程编辑页的节次范围、桌面小组件的行标签全部同步**

### 课表微调

导入的课表经常会「不对」——教室错了、有不上选项课、临时调课。所以做了完整的编辑能力。

点课块或长按课块，都会弹出同一个操作面板：

| 操作 | 说明 |
|---|---|
| 编辑 | 改课名 / 教师 / 地点 / 星期 / 节次 / 周次 |
| 移动到… | 选目标格，再选「所有周」或「仅本周」 |
| 本周停课 | 该周不显示（半透明 + 删除线），不影响其他周 |
| 取消本周调整 | 撤销这一周的停课 / 移动 |
| 删除所有同名课程 | 清「大学英语 / 大学日语」这类二选一的选项课 |
| 删除这门课 | 只删这一个课块 |

另有：AppBar `+` 新增课程、AppBar 撤销（最多 20 步）、设置页「恢复导入的原始课表」。

### 桌面小组件（3 个）

- **下节课**：当前 / 下一节课，跨天自动刷新
- **今日课程**：今天全部课程，最多 4 行
- **一周总课表**：网格视图，预计算未来 3 周，跨周自动切换

**点击任意小组件可直接打开 App。**

三个小组件的**卡片底色、文字颜色、今日高亮**都会跟随主题包，
课程色块跟随课程配色（Android 12+ 完整生效；12 以下回退到内置的亮 / 暗色）。

深浅色跟**你在 App 里选的「主题」**，而不是只跟系统 ——
App 设成深色时小组件也变深色；设成「跟随系统」时则在每次刷新时读取
系统状态，系统切换深浅色后小组件会跟着变。

---

## 课表抓取工具

如果学校教务系统只能网页看课表、导出不了 Excel，`tools/gdust_crawl/` 里有配套的抓取工具。

三种用法，按「傻瓜程度」选：

| 方式 | 需要什么 | 要不要「找请求」 | 适合谁 |
|---|---|---|---|
| **① 图形界面** | 电脑装 Python，双击 `启动.bat` | ❌ **不用** | 只想快点拿到课表（推荐） |
| ② 浏览器控制台 | 什么都不用装 | ✅ 要 | 不想装 Python |
| ③ 命令行 | Python + 手动复制 Cookie | ✅ 要 | 想脚本化 |

三种输出完全一样（`timetable.json`），导入方式也相同。

- 详细步骤见 [`tools/gdust_crawl/TUTORIAL.md`](tools/gdust_crawl/TUTORIAL.md)
- 安全性说明（请求量、服务器能看到什么、使用边界）也在这份教程里
- **工具只读不写**：只查询你自己的课表，不选课、不改任何数据；不保存密码，
  TOKEN 只在内存里用于本次请求

> 这部分是针对**广东科技学院**的教务系统实现的。其他学校欢迎提 PR 适配。

---

## 技术栈

刻意保持简单，不引入状态管理 / 路由 / 数据库框架：

```
Flutter 3.47 / Dart 3.13
状态管理   StatefulWidget + ValueNotifier
本地存储   JSON 文件（原子写：tmp → bak → rename）+ shared_preferences
表格解析   excel_plus（支持老式 .xls）
小组件     home_widget + Kotlin RemoteViews
```

**为什么不用 drift / riverpod / go_router**：这个应用的数据模型极简（一个 `TimetableData`），
引入这些框架带来的抽象成本高于收益。

---

## 隐私

- **不做教务系统登录**，App 内没有任何账号体系
- **不采集、不上传任何数据**，App 运行时不发起任何网络请求
  （应用内更新功能已实现但**默认关闭**，配置项为空时完全离线）
- 课表数据只存在手机本机

抓取课表由用户自己在电脑上完成（导出 Excel 或跑抓取工具），App 只负责导入。

---

## 构建

需要 Flutter 3.47+、JDK 17、Android SDK 36。

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

发布脚本（Windows）：

```powershell
.\tools\release.ps1 -Notes "本次更新说明"
```

会做：解析版本号 → 前置检查 → 构建 → **apksigner 校验签名**（防止误用 debug key 发行）
→ 计算 SHA-256 → 输出到 `release/`。

---

## 项目结构

```
lib/
├── constants/     app_config（应用内更新开关）
├── models/        Course / TimetableData / CourseOverride / Period /
│                  TimetableMeta / ThemePack / PalettePack / UpdateInfo
├── services/      StorageService / SettingsService / WidgetService /
│                  ThemeService / PaletteService / CourseEditor / UndoStack /
│                  UpdateService / ApkInstaller
├── utils/         纯函数：week_mask / week_math / timetable_query / next_class /
│                  today_classes / course_color / widget_skin / period_editor /
│                  breakpoints / timetable_importer / jwxt_excel_importer /
│                  generic_cell_parser / week_grid_model
├── screens/       home / settings / import_flow / import_preview /
│                  semester_setup / course_edit / period_settings
├── widgets/       week_grid / course_block / app_card / course_action_sheet /
│                  course_sheet_parts / pack_actions / theme_pack_sheet /
│                  palette_pack_sheet / time_picker_sheet / update_section
└── theme/         week_grid_dimens（断点尺寸令牌）

tools/
├── release.ps1                  发布脚本
└── gdust_crawl/                 课表抓取工具（GUI + 命令行 + 浏览器控制台）

android/app/src/main/
├── kotlin/        NextClass / Today / WeekWidgetProvider /
│                  WidgetColors / ApkInstaller / MainActivity
└── res/           3 套小组件布局 + 共享设计 token（widget_colors / widget_dimens）
```

`lib/utils/` 下的逻辑全部是**不依赖 Flutter 的纯函数**，可以直接单测。
共 40 个测试文件、437 条测试。

---

## 适配你的学校

Excel 解析针对**正方系统**的紧凑格式调优，并用「表头两级识别 + 星期列映射 +
节次行推断 + 三层单元格解析」尽量兼容其他格式。但仍可能遇到识别不到课程、
课程数量偏少、课名 / 地点 / 教师错位的情况。

**如果你的学校导入不成功，欢迎提交课表样表** —— 拿到真实文件才能针对你的学校适配：

👉 [导入失败 / 课表格式不支持 · 提交 Issue](https://github.com/Planeer-starry/guangke-timetable/issues/new)

提交时请附上教务系统导出的 `.xls` / `.xlsx`，并**先删掉表格顶部的姓名、学号、班级等信息**。

> 解析不完整时也可以先用 App 内的「+」手动添加课程，或用编辑功能修正 ——
> 导入只负责把大部分的活干掉。

---

## 已知限制

- 只做了 Android；iOS / Web / Windows 未做
- 教务 Excel 解析针对**正方系统的紧凑格式**调优，其他学校的导出格式可能解析不全
  （解析不出的条目会走兜底，导入后可用编辑功能手动补）
- 抓取工具目前只适配**广东科技学院**的教务系统
- 小组件的卡片底色 / 文字色需要 **Android 12+** 才能完整跟随主题；
  更低版本会回退到内置的亮 / 暗配色（功能和内容不受影响）
- 主题包 / 课程配色是「配置驱动」的：一份 JSON 描述外观，**不执行任何代码**
  （Flutter AOT 编译没有运行时解释器，做不了真正的动态插件）

---

## 许可证

[MIT](LICENSE) © 2026 Planeer-starry

随便用、随便改、随便参考，保留版权声明即可。
