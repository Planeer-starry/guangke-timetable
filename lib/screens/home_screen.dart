import 'package:flutter/material.dart';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/screens/semester_setup_screen.dart';
import 'package:timetable/services/settings_service.dart';
import 'package:timetable/services/storage_service.dart';
import 'package:timetable/utils/timetable_query.dart';
import 'package:timetable/utils/week_math.dart';
import 'package:timetable/widgets/course_detail_sheet.dart';
import 'package:timetable/widgets/week_grid.dart';

/// 周课表主页面。
///
/// 业务逻辑不写在 build 里：取某周课程用 timetable_query.coursesForWeek，
/// 算当前周次用 week_math.weekOfDate。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialData,
    required this.storage,
    required this.settings,
  });

  final TimetableData initialData;
  final StorageService storage;
  final SettingsService settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ValueNotifier<TimetableData> _data;
  late final ValueNotifier<int> _displayWeek;

  @override
  void initState() {
    super.initState();
    _data = ValueNotifier<TimetableData>(widget.initialData);
    _displayWeek = ValueNotifier<int>(_initialWeek(widget.initialData));
  }

  @override
  void dispose() {
    _data.dispose();
    _displayWeek.dispose();
    super.dispose();
  }

  /// 当前周次：优先用户固定（weekOverride），否则由日历计算。
  int _effectiveWeek(TimetableData data) {
    final int? override = widget.settings.weekOverride;
    if (override != null) {
      return override;
    }
    return weekOfDate(
      DateTime.now(),
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
  }

  int _initialWeek(TimetableData data) {
    if (!data.semesterConfigured) {
      return 1;
    }
    return _effectiveWeek(data);
  }

  /// 翻页：只改内存里的浏览位置，**不写 weekOverride**。
  void _goToWeek(int week, int totalWeeks) {
    final int clamped;
    if (week < 1) {
      clamped = 1;
    } else if (week > totalWeeks) {
      clamped = totalWeeks;
    } else {
      clamped = week;
    }
    _displayWeek.value = clamped;
  }

  /// 回到本周：**清除**周次覆盖（恢复跟随日历），再把内存设为本周。
  Future<void> _backToCurrentWeek(TimetableData data) async {
    await widget.settings.setWeekOverride(null);
    _displayWeek.value = weekOfDate(
      DateTime.now(),
      data.meta.week1Monday,
      data.meta.totalWeeks,
    );
  }

  /// 打开学期设置页；保存成功会返回新的 TimetableData。
  Future<void> _openSemesterSetup() async {
    final TimetableData? updated = await Navigator.of(context)
        .push<TimetableData>(
          MaterialPageRoute<TimetableData>(
            builder: (_) =>
                SemesterSetupScreen(data: _data.value, storage: widget.storage),
          ),
        );
    if (updated == null) {
      return;
    }
    _data.value = updated;
    _displayWeek.value = _effectiveWeek(updated);
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('导入功能即将上线，敬请期待')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<TimetableData>(
          valueListenable: _data,
          builder: (BuildContext context, TimetableData data, _) {
            return Text(
              data.meta.semesterName.isEmpty ? '广科课表' : data.meta.semesterName,
            );
          },
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '设置学期',
            icon: const Icon(Icons.settings),
            onPressed: _openSemesterSetup,
          ),
        ],
      ),
      body: ValueListenableBuilder<TimetableData>(
        valueListenable: _data,
        builder: (BuildContext context, TimetableData data, _) {
          if (!data.semesterConfigured) {
            return _buildSetupGuide(context);
          }
          return _buildTimetable(context, data);
        },
      ),
    );
  }

  /// 学期未设置时的引导（首次启动必经）。
  Widget _buildSetupGuide(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.event, size: 64),
            const SizedBox(height: 16),
            const Text('还没有设置学期开始日，点这里设置第一周周一'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _openSemesterSetup,
              child: const Text('设置第一周周一'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimetable(BuildContext context, TimetableData data) {
    return ValueListenableBuilder<int>(
      valueListenable: _displayWeek,
      builder: (BuildContext context, int week, _) {
        final List<CourseOccurrence> occurrences = coursesForWeek(data, week);
        final DateTime monday = mondayOfWeek(data.meta.week1Monday, week);
        final bool isCurrentWeek = week == _effectiveWeek(data);
        return Column(
          children: <Widget>[
            _buildWeekBar(context, week, data),
            const Divider(height: 1),
            Expanded(
              child: occurrences.isEmpty
                  ? _buildEmptyWeek(context)
                  : WeekGrid(
                      periods: data.periods,
                      occurrences: occurrences,
                      weekMonday: monday,
                      isCurrentWeek: isCurrentWeek,
                      onCourseTap: (CourseOccurrence occurrence) =>
                          showCourseDetailSheet(
                            context,
                            occurrence: occurrence,
                            periods: data.periods,
                            week: week,
                          ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWeekBar(BuildContext context, int week, TimetableData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: '上一周',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _goToWeek(week - 1, data.meta.totalWeeks),
          ),
          Expanded(child: Center(child: Text('第 $week 周'))),
          IconButton(
            tooltip: '下一周',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _goToWeek(week + 1, data.meta.totalWeeks),
          ),
          TextButton(
            onPressed: () => _backToCurrentWeek(data),
            child: const Text('回到本周'),
          ),
        ],
      ),
    );
  }

  /// 该周没有课程时的空状态。
  Widget _buildEmptyWeek(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.event_busy, size: 64),
          const SizedBox(height: 16),
          const Text('还没有课表'),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () => _showComingSoon(context),
            child: const Text('导入课表（敬请期待）'),
          ),
        ],
      ),
    );
  }
}
