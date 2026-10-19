# 简课表

一个专注于**广东科技学院**的 Android 课表应用。Flutter 编写，单机离线，数据全部存在本机。

> 为「教务系统只能网页看课表」这个痛点做的。导入一次，之后开 App 或看桌面小组件就行。

---

## 功能

### 课表
- 周视图网格，连堂自动合并、单双周区分、今天列高亮
- **左右滑动换周**，边缘回弹；「回到本周」按需显示
- 深色模式；平板/手机自适应布局（<600 / 600–840 / ≥840dp 三档断点）

### 导入
- **教务系统 Excel 导入**（`.xls` / `.xlsx`）：自动识别学期名、第一周周一、总周数、节次与周次
- 广科 JSON 导入（按周展开格式）、剪贴板导入
- 导入预览：识别到的课程数、学期信息、被跳过的条目

### 桌面小组件（3 个）
- **下节课**：当前/下一节课，跨天自动刷新
- **今日课程**：今天全部课程，最多 4 行
- **一周总课表**：6×4 网格，预计算未来 3 周，跨周自动切换

### 课表微调

导入的课表经常会「不对」——教室错了、有不上选项课、临时调课。所以做了完整的编辑能力：

| 操作 | 入口 |
|---|---|
| 新增课程 | AppBar `+` |
| 编辑课程 | 点课块 → 编辑 |
| 删除课程 | 点课块 → 删除 |
| **按课名批量删除** | 长按 → 删除所有同名课程（清「大学英语/日语」这类二选一的选项课） |
| 移动课程 | 长按 → 移动到… → 点目标格 → 选「所有周」或「仅本周」 |
| 本周停课 | 点课块 → 本周停课（半透明 + 删除线） |
| 撤销 | AppBar 撤销按钮，最多 20 步 |
| 恢复导入原始 | 设置页（导入时自动存快照） |

---

## 技术栈

刻意保持简单，不引入状态管理/路由/数据库框架：

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
- 不采集、不上传任何数据，也不联网（除可选的「检查更新」，默认关闭）
- 课表数据只存在手机本机

抓取课表由用户自己在电脑上完成（导出 Excel 或跑外部脚本），App 只负责导入。

---

## 构建

需要 Flutter 3.47+、JDK 17、Android SDK 36。

```bash
flutter pub get
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
├── models/        Course / TimetableData / CourseOverride / Period / TimetableMeta
├── services/      StorageService / SettingsService / WidgetService /
│                  CourseEditor / UndoStack
├── utils/         纯函数：week_mask / week_math / timetable_query / next_class /
│                  course_color / breakpoints / timetable_importer / jwxt_excel_importer
├── screens/       home / settings / import_flow / import_preview / semester_setup /
│                  course_edit
├── widgets/       week_grid / course_block / course_detail_sheet / update_section
└── theme/         week_grid_dimens（断点尺寸令牌）

android/app/src/main/
├── kotlin/        NextClassWidgetProvider / TodayWidgetProvider / WeekWidgetProvider /
│                  ApkInstaller
└── res/           3 套小组件布局 + 共享设计 token（widget_colors / widget_dimens）
```

`lib/utils/` 下的逻辑全部是**不依赖 Flutter 的纯函数**，可以直接单测。
共 24 个测试文件、210+ 条测试。

---

## 适配你的学校

目前 Excel 解析主要针对**正方系统**的紧凑格式调优。其他学校的导出格式可能识别不到课程、
课程数量偏少，或者课名 / 地点 / 教师错位。

**如果你的学校导入不成功，欢迎提交课表样表** —— 拿到真实文件才能针对你的学校适配：

👉 [导入失败 / 课表格式不支持 · 提交 Issue](https://github.com/Planeer-starry/jiankebiao/issues/new?template=import-failure.yml)

提交时请附上教务系统导出的 `.xls` / `.xlsx`，并**先删掉表格顶部的姓名、学号、班级等信息**。

> 解析不完整时也可以先用 App 内的「+」手动添加课程，或用编辑功能修正 ——
> 导入只负责把大部分的活干掉。

---

## 已知限制

- 只做了 Android；iOS / Web / Windows 未做
- 教务 Excel 解析目前针对**正方系统的紧凑格式**调优，其他学校的导出格式可能解析不全
  （解析不出的条目会走兜底，导入后可用编辑功能手动补）
- 节次时间默认是广科的 10 节作息，其他学校需自行调整数据

---

## 许可证

[MIT](LICENSE) © 2026 Planeer-starry

随便用、随便改、随便参考，保留版权声明即可。
