import 'package:flutter/material.dart';

import 'package:timetable/models/course.dart';
import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/services/course_editor.dart';
import 'package:timetable/utils/course_color.dart';
import 'package:timetable/utils/week_mask.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '新增课程' : '编辑课程'),
        actions: <Widget>[
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextFormField(
            controller: _nameController,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '课程名'),
          ),
          TextFormField(
            controller: _teacherController,
            decoration: const InputDecoration(labelText: '教师（可选）'),
          ),
          TextFormField(
            controller: _locationController,
            decoration: const InputDecoration(labelText: '地点（可选）'),
          ),
          const SizedBox(height: 24),
          _buildDayPicker(context),
          const SizedBox(height: 16),
          _buildSectionPicker(context),
          const SizedBox(height: 16),
          _buildWeekPicker(context),
          _buildConflictHint(context),
        ],
      ),
    );
  }

  Widget _buildDayPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('星期', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (int day = 1; day <= 7; day++)
              ChoiceChip(
                label: Text('周${_dayNames[day - 1]}'),
                selected: _dayWeek == day,
                onSelected: (_) => setState(() => _dayWeek = day),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionPicker(BuildContext context) {
    final List<DropdownMenuItem<int>> items = <DropdownMenuItem<int>>[
      for (int i = 1; i <= widget.data.periods.length; i++)
        DropdownMenuItem<int>(value: i, child: Text('$i')),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('节次', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            const Text('第'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _sectionStart,
              items: items,
              onChanged: (int? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sectionStart = value;
                  // start 升过 end 时 end 跟上，保证 start <= end
                  if (_sectionEnd < _sectionStart) {
                    _sectionEnd = _sectionStart;
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            const Text('节 至 第'),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _sectionEnd,
              items: items,
              onChanged: (int? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _sectionEnd = value;
                  // 对称防御：end 降到 start 以下时 start 跟着降
                  if (_sectionStart > _sectionEnd) {
                    _sectionStart = _sectionEnd;
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            const Text('节'),
          ],
        ),
      ],
    );
  }

  Widget _buildWeekPicker(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('周次', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: <Widget>[
            TextButton(
              onPressed: () => setState(
                () => _selectedWeeks = <int>{
                  for (int w = 1; w <= _totalWeeks; w++) w,
                },
              ),
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: () => setState(() => _selectedWeeks = <int>{}),
              child: const Text('清空'),
            ),
            TextButton(
              onPressed: () => setState(
                () => _selectedWeeks = <int>{
                  for (int w = 1; w <= _totalWeeks; w++)
                    if (w.isOdd) w,
                },
              ),
              child: const Text('单周'),
            ),
            TextButton(
              onPressed: () => setState(
                () => _selectedWeeks = <int>{
                  for (int w = 1; w <= _totalWeeks; w++)
                    if (w.isEven) w,
                },
              ),
              child: const Text('双周'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
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
      ],
    );
  }

  /// 冲突提示（非阻塞，amber 底）：只在有冲突时渲染。
  Widget _buildConflictHint(BuildContext context) {
    final List<Course> conflicts = _conflictingCourses();
    if (conflicts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '该时段已有 ${conflicts.length} 门课：'
              '${conflicts.map((Course c) => c.name).join('、')}',
              style: TextStyle(color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }
}
