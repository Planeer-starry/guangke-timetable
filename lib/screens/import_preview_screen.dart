import 'package:flutter/material.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/utils/timetable_importer.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/utils/week_math.dart';

/// 导入预览页：显示识别结果，确认后 pop 传回 `List<Course>`。
class ImportPreviewScreen extends StatelessWidget {
  const ImportPreviewScreen({super.key, required this.result});

  final ImportResult result;

  @override
  Widget build(BuildContext context) {
    final List<Course> courses = result.courses.toList()
      ..sort((Course a, Course b) {
        final int byDay = a.dayWeek.compareTo(b.dayWeek);
        if (byDay != 0) {
          return byDay;
        }
        return a.sectionStart.compareTo(b.sectionStart);
      });
    final Set<int> allWeeks = <int>{};
    for (final Course course in courses) {
      allWeeks.addAll(weeksFromWeekMask(course.weekMask));
    }
    final String weekRange = formatWeekRanges(allWeeks.toList());
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      body: Column(
        children: <Widget>[
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('识别出 ${courses.length} 门课'),
                  const SizedBox(height: 4),
                  Text('覆盖周次：$weekRange'),
                  if (result.skippedCount > 0)
                    Text(
                      '跳过 ${result.skippedCount} 条无法解析的记录',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: courses.length,
              itemBuilder: (BuildContext context, int index) {
                final Course course = courses[index];
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(courses),
            child: const Text('确认导入'),
          ),
        ),
      ),
    );
  }

  String _weekdayName(int dayWeek) {
    if (dayWeek < 1 || dayWeek > 7) {
      return '?';
    }
    return '一二三四五六日'[dayWeek - 1];
  }
}
