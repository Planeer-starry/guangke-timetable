import 'package:flutter/material.dart';

import 'package:timetable/models/timetable_data.dart';
import 'package:timetable/models/timetable_meta.dart';
import 'package:timetable/services/storage_service.dart';

/// 学期设置页：选第一周周一 + 填总周数，写回 timetable.json 的 meta。
///
/// 这是首次启动必经流程——首次打开不可能是已配置状态。
/// 日期选择器用 selectableDayPredicate 只允许选周一，
/// 从源头保证 week1Monday 的语义正确。
class SemesterSetupScreen extends StatefulWidget {
  const SemesterSetupScreen({
    super.key,
    required this.data,
    required this.storage,
  });

  final TimetableData data;
  final StorageService storage;

  @override
  State<SemesterSetupScreen> createState() => _SemesterSetupScreenState();
}

class _SemesterSetupScreenState extends State<SemesterSetupScreen> {
  late DateTime _selectedMonday;
  late int _totalWeeks;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final bool configured =
        widget.data.meta.week1Monday != TimetableData.unsetWeek1Monday;
    _selectedMonday = configured
        ? widget.data.meta.week1Monday
        : _thisMonday(DateTime.now());
    _totalWeeks = widget.data.meta.totalWeeks;
  }

  /// 本周一（本地日期）。
  DateTime _thisMonday(DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  Future<void> _pickMonday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonday,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      // 只允许选周一，从源头保证 week1Monday 语义
      selectableDayPredicate: (DateTime day) => day.weekday == DateTime.monday,
      helpText: '选择第一周的周一',
    );
    if (picked == null || picked == _selectedMonday) {
      return;
    }
    setState(() {
      _selectedMonday = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final TimetableMeta oldMeta = widget.data.meta;
    final TimetableData updated = TimetableData(
      schema: widget.data.schema,
      meta: TimetableMeta(
        school: oldMeta.school,
        semesterName: oldMeta.semesterName,
        week1Monday: DateTime(
          _selectedMonday.year,
          _selectedMonday.month,
          _selectedMonday.day,
        ),
        totalWeeks: _totalWeeks,
      ),
      periods: widget.data.periods,
      courses: widget.data.courses,
      overrides: widget.data.overrides,
    );
    try {
      await widget.storage.save(updated);
    } catch (error) {
      // save 失败必须给用户可见提示，禁止静默吞掉
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      return;
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置学期')),
      // 表单限宽居中（平板/横屏）：ConstrainedBox 在窄屏（<560）上
      // 不产生约束，行为与不包完全一致，因此无需断点判断
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('第一周周一'),
                subtitle: Text(_formatDate(_selectedMonday)),
                trailing: const Icon(Icons.edit_calendar),
                onTap: _saving ? null : _pickMonday,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _totalWeeks.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '总周数',
                  border: OutlineInputBorder(),
                ),
                enabled: !_saving,
                onChanged: (String value) {
                  final int? parsed = int.tryParse(value);
                  if (parsed == null || parsed < 1) {
                    return;
                  }
                  setState(() => _totalWeeks = parsed);
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
