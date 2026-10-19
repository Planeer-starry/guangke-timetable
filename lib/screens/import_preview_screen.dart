import 'package:flutter/material.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/course_override.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/utils/jwxt_excel_importer.dart';
import 'package:timetable/utils/period_editor.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';
import 'package:timetable/widgets/app_card.dart';

/// 预览页确认后的返回值：课程列表 + 可选学期三件套 + 可选作息 + 可选调整。
///
/// 学期三件套在教务 Excel（从注释行识别）或 JSON 携带 meta 时非 null，
/// 用户确认后写入 meta，免去手动设置学期。
/// [periods] 是文件里识别 / 携带的作息，null 或空 = 沿用现有
///（绝不缩水，见 import_flow 的 `_applyImported`）。
/// [overrides] 仅简课表备份导入时非 null（完整恢复停课 / 移动调整），
/// 其余来源为 null = 导入后清空旧调整。
class ImportConfirmation {
  const ImportConfirmation({
    required this.courses,
    this.week1Monday,
    this.totalWeeks,
    this.semesterName,
    this.periods,
    this.overrides,
  });

  final List<Course> courses;
  final DateTime? week1Monday;
  final int? totalWeeks;
  final String? semesterName;
  final List<Period>? periods;
  final List<CourseOverride>? overrides;
}

/// 导入预览页：显示识别结果与学期信息，确认后 pop 传回 [ImportConfirmation]。
class ImportPreviewScreen extends StatelessWidget {
  const ImportPreviewScreen({
    super.key,
    required this.courses,
    required this.skippedCount,
    this.jwxt,
    this.currentMeta,
    this.importedMeta,
    this.importedPeriods,
    this.importedOverrides,
    this.isFullBackup = false,
  });

  /// 解析出的课程（排序展示；确认后原样带回）。
  final List<Course> courses;

  /// 跳过条数（两种导入来源通用）。
  final int skippedCount;

  /// 教务 Excel 导入的完整结果（用其学期三件套）；JSON 导入为 null。
  final JwxtImportResult? jwxt;

  /// 当前已配置学期（显示「将修改 / 覆盖学期设置」警告用）。
  final TimetableMeta? currentMeta;

  /// JSON（教务 / 爬虫 / App 备份）里携带的学期信息；未携带或校验
  /// 不过时为 null，此时学期维持现状。
  final TimetableMeta? importedMeta;

  /// JSON 里携带的作息时间表；未携带或校验不过时为 null（沿用现有）。
  final List<Period>? importedPeriods;

  /// App 备份里携带的当周调整；确认后原样带回完整恢复。
  final List<CourseOverride>? importedOverrides;

  /// 是否为简课表备份文件（导入将完整恢复学期、作息与当周调整）。
  final bool isFullBackup;

  @override
  Widget build(BuildContext context) {
    final List<Course> sorted = courses.toList()
      ..sort((Course a, Course b) {
        final int byDay = a.dayWeek.compareTo(b.dayWeek);
        if (byDay != 0) {
          return byDay;
        }
        return a.sectionStart.compareTo(b.sectionStart);
      });
    final Set<int> allWeeks = <int>{};
    for (final Course course in sorted) {
      allWeeks.addAll(weeksFromWeekMask(course.weekMask));
    }
    final String weekRange = formatWeekRanges(allWeeks.toList());
    final bool hasJwxtMeta = jwxt?.hasMeta == true;
    final bool semesterChanging =
        hasJwxtMeta &&
        currentMeta != null &&
        currentMeta!.week1Monday != TimetableData.unsetWeek1Monday &&
        currentMeta!.week1Monday != jwxt!.week1Monday;
    // —— JSON 携带的学期 / 作息（教务 / 爬虫可选提供，App 备份必有）——
    final TimetableMeta? imported = importedMeta;
    final bool currentConfigured =
        currentMeta != null && currentMeta!.week1Monday.year > 1;
    final bool semesterOverriding =
        imported != null &&
        currentConfigured &&
        (currentMeta!.week1Monday != imported.week1Monday ||
            currentMeta!.totalWeeks != imported.totalWeeks);
    final String? semesterLabel = imported == null
        ? null
        : _importedSemesterLabel(imported);
    final bool hasImportedSettings =
        imported != null || importedPeriods != null;
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      // 内容限宽居中（平板/横屏）：ConstrainedBox 在窄屏（<720）上
      // 不产生约束，行为与不包完全一致，因此无需断点判断
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: <Widget>[
              Card(
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (isFullBackup) ...<Widget>[
                        Text(
                          '这是简课表的备份文件，导入会完整恢复学期、作息、'
                          '以及所有停课 / 移动调整',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text('识别出 ${sorted.length} 门课'),
                      const SizedBox(height: 4),
                      Text('覆盖周次：$weekRange'),
                      if (skippedCount > 0)
                        Text(
                          '跳过 $skippedCount 条无法解析的记录',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (hasJwxtMeta) ...<Widget>[
                        const Divider(height: 16),
                        Text('识别到学期：${jwxt!.semesterName ?? '未命名'}'),
                        const SizedBox(height: 2),
                        Text('第一周周一：${_formatDate(jwxt!.week1Monday!)}（自动填写）'),
                        const SizedBox(height: 2),
                        Text('总周数：${jwxt!.totalWeeks} 周'),
                      ],
                      // 作息行（仅教务 Excel）：三态展示，绝不缩水
                      if (jwxt != null) ...<Widget>[
                        if (hasJwxtMeta)
                          const SizedBox(height: 2)
                        else
                          const Divider(height: 16),
                        Text(_periodsSummary()),
                      ],
                      if (jwxt != null && jwxt!.fallbackCount > 0) ...<Widget>[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${jwxt!.fallbackCount} 条课程只识别出名称，'
                                '导入后可手动补全地点与教师',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (semesterChanging) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          '⚠️ 将修改学期设置：'
                          '${_formatDate(currentMeta!.week1Monday)} → '
                          '${_formatDate(jwxt!.week1Monday!)}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (hasImportedSettings)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: AppCard(
                    title: '将同时设置',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (semesterLabel != null) ...<Widget>[
                          Text('学期：$semesterLabel'),
                          const SizedBox(height: 2),
                        ],
                        if (imported != null) ...<Widget>[
                          Text(
                            '第一周：${_formatDate(imported.week1Monday)}'
                            ' · 共 ${imported.totalWeeks} 周',
                          ),
                          const SizedBox(height: 2),
                        ],
                        if (importedPeriods != null)
                          Text('作息：${periodsSummary(importedPeriods!)}'),
                        if (semesterOverriding) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            '⚠️ 将覆盖当前学期设置'
                            '（原：${_formatDate(currentMeta!.week1Monday)}）',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: sorted.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Course course = sorted[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          color: Color(course.colorValue),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(course.name),
                      subtitle: Text(
                        '${_weekdayName(course.dayWeek)} '
                        '第${course.sectionStart}-${course.sectionEnd}节'
                        '${course.teacher.isEmpty ? '' : ' · ${course.teacher}'}'
                        '${course.location.isEmpty ? '' : ' · ${course.location}'}\n'
                        '${formatWeekRanges(weeksFromWeekMask(course.weekMask))}',
                      ),
                      isThreeLine: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(
              ImportConfirmation(
                courses: sorted,
                week1Monday: jwxt?.week1Monday ?? importedMeta?.week1Monday,
                totalWeeks: jwxt?.totalWeeks ?? importedMeta?.totalWeeks,
                semesterName: jwxt?.semesterName ?? importedMeta?.semesterName,
                periods: jwxt?.periods ?? importedPeriods,
                overrides: importedOverrides,
              ),
            ),
            child: const Text('确认导入'),
          ),
        ),
      ),
    );
  }

  /// JSON 携带学期行的文案：优先学期名，其次学校名，都空返回 null（不显示）。
  String? _importedSemesterLabel(TimetableMeta meta) {
    if (meta.semesterName.trim().isNotEmpty) {
      return meta.semesterName;
    }
    if (meta.school.trim().isNotEmpty) {
      return meta.school;
    }
    return null;
  }

  /// 作息摘要行：识别自表格时列出前 3 个节次时间，否则沿用默认。
  String _periodsSummary() {
    final JwxtImportResult result = jwxt!;
    final List<Period> periods = result.periods ?? const <Period>[];
    if (result.usedDefaultPeriods || periods.isEmpty) {
      return '作息：沿用默认 10 节';
    }
    final List<String> head = <String>[
      for (final Period p in periods.take(3)) '${p.start}-${p.end}',
    ];
    final String more = periods.length > 3 ? '…' : '';
    return '作息：${periods.length} 节（识别自表格）${head.join('，')}$more';
  }

  String _weekdayName(int dayWeek) {
    if (dayWeek < 1 || dayWeek > 7) {
      return '?';
    }
    return '一二三四五六日'[dayWeek - 1];
  }

  String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
