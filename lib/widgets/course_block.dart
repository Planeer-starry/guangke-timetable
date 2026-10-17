import 'package:flutter/material.dart';

import 'package:timetable/models/period.dart';
import 'package:timetable/utils/timetable_query.dart';

/// 课程块：按 dayWeek / sectionStart~sectionEnd 定位（由 WeekGrid 负责），
/// 这里只负责渲染。空间不够时用省略号。
class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.occurrence,
    required this.periods,
    required this.onTap,
  });

  final CourseOccurrence occurrence;
  final List<Period> periods;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(occurrence.course.colorValue);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  occurrence.course.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
                if (occurrence.location.isNotEmpty)
                  Text(
                    occurrence.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
