import 'package:flutter/material.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/period.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/course_editor.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/week_mask.dart';
import 'package:timetable/widgets/app_card.dart';

/// 新增 / 编辑课程页。
///
/// 模式与 semester_setup_screen 一致：**页面不碰 storage**，
/// 保存后 `Navigator.pop(context, TimetableData)` 交回调用方持久化。
///
/// 颜色策略：新增课按课程名取色（colorValueFromName）；
/// 编辑课保持原色不变（不按新名称重算，避免用户眼里的课块突然变色）。
class CourseEditScreen extends StatefulWidget {
  const CourseEditScreen({
    super.key,
    required this.data,
    this.course,
    this.defaultDayWeek,
    this.defaultWeek,
  });

  /// 当前课表数据（生成 id / 冲突检测）。
  final TimetableData data;

  /// null = 新增；非 null = 编辑该课。
  final Course? course;

  /// 新增时预选星期（null → 周一）。
  final int? defaultDayWeek;

  /// 新增时若给了，周次默认只选这一周；否则全选。
  final int? defaultWeek;

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _teacherController;
  late final TextEditingController _locationController;
  late int _dayWeek;
  late int _sectionStart;
  late int _sectionEnd;
  late Set<int> _selectedWeeks;

  static const List<String> _dayNames = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  int get _totalWeeks => widget.data.meta.totalWeeks;

  @override
  void initState() {
    super.initState();
    final Course? course = widget.course;
    _nameController = TextEditingController(text: course?.name ?? '');
    _teacherController = TextEditingController(text: course?.teacher ?? '');
    _locationController = TextEditingController(text: course?.location ?? '');
    if (course != null) {
      _dayWeek = course.dayWeek;
      _sectionStart = course.sectionStart;
      _sectionEnd = course.sectionEnd;
      _selectedWeeks = weeksFromWeekMask(course.weekMask).toSet();
    } else {
      _dayWeek = widget.defaultDayWeek ?? 1;
      _sectionStart = 1;
      _sectionEnd = 1;
      if (widget.defaultWeek != null) {
        final int week = widget.defaultWeek!.clamp(1, _totalWeeks);
        _selectedWeeks = <int>{week};
      } else {
        _selectedWeeks = <int>{for (int w = 1; w <= _totalWeeks; w++) w};
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teacherController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// 与现有其它课程（排除自身）的冲突：同星期、节次区间相交、
  /// 且所选周次中至少一周撞上。仅用于提示，不阻止保存。
  List<Course> _conflictingCourses() {
    return widget.data.courses.where((Course other) {
      if (other.id == widget.course?.id) {
        return false;
      }
      if (other.dayWeek != _dayWeek) {
        return false;
      }
      if (other.sectionEnd < _sectionStart ||
          other.sectionStart > _sectionEnd) {
        return false;
      }
      return _selectedWeeks.any(
        (int week) => hasClassInWeek(other.weekMask, week),
      );
    }).toList();
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('请填写课程名');
      return;
    }
    if (_selectedWeeks.isEmpty) {
      _toast('请至少选择一个周次');
      return;
    }
    if (_sectionStart > _sectionEnd) {
      _toast('起始节次不能大于结束节次');
      return;
    }
    final int weekMask = weekMaskFromWeeks(_selectedWeeks);
    final String teacher = _teacherController.text.trim();
    final String location = _locationController.text.trim();
    final Course saved;
    if (widget.course == null) {
      // 新增：id 用 u_ 前缀，颜色按课程名稳定取色
      saved = Course(
        id: CourseEditor.newCourseId(widget.data),
        name: name,
        teacher: teacher,
        location: location,
        colorValue: colorValueFromName(name),
        dayWeek: _dayWeek,
        sectionStart: _sectionStart,
        sectionEnd: _sectionEnd,
        weekMask: weekMask,
      );
    } else {
      // 编辑：id 与颜色保持不变（copyWith 不传 colorValue 即沿用）
      saved = widget.course!.copyWith(
        name: name,
        teacher: teacher,
        location: location,
        dayWeek: _dayWeek,
        sectionStart: _sectionStart,
        sectionEnd: _sectionEnd,
        weekMask: weekMask,
      );
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(CourseEditor.upsertCourse(widget.data, saved));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Scaffold(
      // 页面淡灰 + 白色卡片：卡片才浮得起来（同色会糊成一片灰）
      backgroundColor: appPageBackground(colors),
      appBar: AppBar(
        title: Text(widget.course == null ? '新增课程' : '编辑课程'),
        actions: <Widget>[
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      // 平板（≥840dp）上表单铺满会拉得极宽、控件全散开，
      // 因此限宽 720 居中；手机（<720）自然铺满，不需要另写一套布局。
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              AppCard(
                title: '基本信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextFormField(
                      controller: _nameController,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: '课程名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _teacherController,
                      decoration: const InputDecoration(
                        labelText: '教师（可选）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _locationController,
                      decoration: const InputDecoration(
                        labelText: '地点（可选）',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                title: '时间',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const AppFieldLabel('星期'),
                    _buildDayPicker(context),
                    const SizedBox(height: 18),
                    const AppFieldLabel('节次'),
                    _buildSectionPicker(context),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(title: '周次', child: _buildWeekPicker(context)),
              _buildConflictHint(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 星期选择：7 个 ChoiceChip（与周次 chips 同一套控件语汇）。
  Widget _buildDayPicker(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int day = 1; day <= 7; day++)
          ChoiceChip(
            label: Text('周${_dayNames[day - 1]}'),
            selected: _dayWeek == day,
            onSelected: (_) => setState(() => _dayWeek = day),
          ),
      ],
    );
  }

  /// 节次选择：起止两个下拉框 + 右侧实时时间范围提示。
  ///
  /// 顺带补了原来的一个体验缺口：选完节次看不到对应几点上课，
  /// 现在「08:30-09:15」直接显示在旁边。
  Widget _buildSectionPicker(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<Period> periods = widget.data.periods;
    final List<DropdownMenuItem<int>> items = <DropdownMenuItem<int>>[
      for (int i = 1; i <= periods.length; i++)
        DropdownMenuItem<int>(value: i, child: Text('第$i节')),
    ];

    Widget dropdown(int value, ValueChanged<int> onChanged) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            items: items,
            onChanged: (int? picked) {
              if (picked != null) {
                onChanged(picked);
              }
            },
          ),
        ),
      );
    }

    final String timeRange = _sectionTimeRange();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: <Widget>[
        dropdown(
          _sectionStart,
          (int picked) => setState(() {
            _sectionStart = picked;
            // 起始升过结束 → 结束跟上，保证 start <= end
            if (_sectionEnd < _sectionStart) {
              _sectionEnd = _sectionStart;
            }
          }),
        ),
        const Text('至'),
        dropdown(
          _sectionEnd,
          (int picked) => setState(() {
            _sectionEnd = picked;
            // 对称防御：结束降到起始以下 → 起始跟着降
            if (_sectionStart > _sectionEnd) {
              _sectionStart = _sectionEnd;
            }
          }),
        ),
        if (timeRange.isNotEmpty)
          Text(
            timeRange,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
      ],
    );
  }

  /// 起始节开始时间 - 结束节结束时间；作息里查不到对应节次时返回空串。
  String _sectionTimeRange() {
    final List<Period> periods = widget.data.periods;
    Period? start;
    Period? end;
    for (final Period period in periods) {
      if (period.index == _sectionStart) {
        start = period;
      }
      if (period.index == _sectionEnd) {
        end = period;
      }
    }
    if (start == null || end == null) {
      return '';
    }
    return '${start.start}-${end.end}';
  }

  /// 周次选择：4 个快捷按钮 + 逐周 FilterChip。
  Widget _buildWeekPicker(BuildContext context) {
    void selectAll() => setState(
      () => _selectedWeeks = <int>{
        for (int w = 1; w <= _totalWeeks; w++) w,
      },
    );
    void clearAll() => setState(() => _selectedWeeks = <int>{});
    void selectOdd() => setState(
      () => _selectedWeeks = <int>{
        for (int w = 1; w <= _totalWeeks; w++)
          if (w.isOdd) w,
      },
    );
    void selectEven() => setState(
      () => _selectedWeeks = <int>{
        for (int w = 1; w <= _totalWeeks; w++)
          if (w.isEven) w,
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton(onPressed: selectAll, child: const Text('全选')),
            OutlinedButton(onPressed: clearAll, child: const Text('清空')),
            OutlinedButton(onPressed: selectOdd, child: const Text('单周')),
            OutlinedButton(onPressed: selectEven, child: const Text('双周')),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (int w = 1; w <= _totalWeeks; w++)
              FilterChip(
                label: Text('$w'),
                selected: _selectedWeeks.contains(w),
                onSelected: (bool selected) => setState(() {
                  if (selected) {
                    _selectedWeeks.add(w);
                  } else {
                    _selectedWeeks.remove(w);
                  }
                }),
              ),
          ],
        ),
        if (_selectedWeeks.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '还没选周次——保存后这门课不会出现在任何一周',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  /// 冲突提示（非阻塞）：只在有冲突时渲染。
  ///
  /// 颜色走主题的 tertiaryContainer 而不是硬编码 amber——
  /// 硬编码在深色模式下会变成刺眼的浅黄底 + 深色字。
  Widget _buildConflictHint(BuildContext context) {
    final List<Course> conflicts = _conflictingCourses();
    if (conflicts.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: colors.onTertiaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '该时段已有 ${conflicts.length} 门课：'
                '${conflicts.map((Course c) => c.name).join('、')}',
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
