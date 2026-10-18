import 'package:flutter_test/flutter_test.dart';

import 'package:timetable/utils/generic_cell_parser.dart';
// 第 1 层在 jwxt_excel_importer（本测试验证两层衔接：正方格式仍归它管）
import 'package:timetable/utils/jwxt_excel_importer.dart'
    show JwxtCellEntry, parseCellText;

void main() {
  group('第 1 层不回归（正方格式仍由 parseCellText 精确解析）', () {
    test('军事理论正方格式：六字段全部正确', () {
      final List<JwxtCellEntry> entries = parseCellText(
        '军事理论/(1-2节)11-14周/松山湖 松6-604/华康/x/26班/90/ /',
      );
      expect(entries, hasLength(1));
      final JwxtCellEntry e = entries.single;
      expect(e.name, '军事理论');
      expect(e.sectionStart, 1);
      expect(e.sectionEnd, 2);
      expect(e.weeks, <int>{11, 12, 13, 14});
      expect(e.location, '松6-604');
      expect(e.teacher, '华康');
    });
  });

  group('第 2 层 parseGenericCell', () {
    test('青果风格多行：课名/教师/周次/地点，节次未知', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '高等数学\n张三\n1-16周\n教1-201',
      );
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '高等数学');
      expect(e.teacher, '张三');
      expect(e.weeks, {for (int i = 1; i <= 16; i++) i});
      expect(e.location, '教1-201');
      expect(e.sectionStart, isNull);
      expect(e.sectionEnd, isNull);
      expect(e.fallback, isFalse);
    });

    test('单行空格分隔：同多行', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '高等数学 张三 1-16周 教1-201',
      );
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '高等数学');
      expect(e.teacher, '张三');
      expect(e.weeks, {for (int i = 1; i <= 16; i++) i});
      expect(e.location, '教1-201');
    });

    test('方括号周次：高等数学[1-16周]', () {
      final List<GenericCellEntry> entries = parseGenericCell('高等数学[1-16周]');
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '高等数学');
      expect(e.weeks, {for (int i = 1; i <= 16; i++) i});
      expect(e.teacher, isEmpty);
      expect(e.location, isEmpty);
    });

    test('只有课名：节次未知、周次空（调用方补全）', () {
      final List<GenericCellEntry> entries = parseGenericCell('高等数学');
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '高等数学');
      expect(e.sectionStart, isNull);
      expect(e.sectionEnd, isNull);
      expect(e.weeks, isEmpty);
      expect(e.fallback, isFalse);
    });

    test('单双周：大学英语(1-16周,双) → 偶数周', () {
      final List<GenericCellEntry> entries = parseGenericCell('大学英语(1-16周,双)');
      expect(entries.single.weeks, {2, 4, 6, 8, 10, 12, 14, 16});
      expect(entries.single.name, '大学英语');
    });

    test('单双周：大学英语 1-16周(双) → 偶数周', () {
      final List<GenericCellEntry> entries = parseGenericCell('大学英语 1-16周(双)');
      expect(entries.single.weeks, {2, 4, 6, 8, 10, 12, 14, 16});
      expect(entries.single.name, '大学英语');
      expect(entries.single.teacher, isEmpty);
    });

    test('课名含数字字母：不能被误判成节次/地点/教师', () {
      expect(parseGenericCell('C语言程序设计C').single.name, 'C语言程序设计C');
      expect(parseGenericCell('大学英语Ⅰ').single.name, '大学英语Ⅰ');
      expect(parseGenericCell('Python数据分析').single.name, 'Python数据分析');
      expect(parseGenericCell('高等数学BⅡ').single.name, '高等数学BⅡ');
      // 这些课名段也不该被当成周次/节次/地点
      final GenericCellEntry e = parseGenericCell('Python数据分析').single;
      expect(e.weeks, isEmpty);
      expect(e.sectionStart, isNull);
      expect(e.location, isEmpty);
    });

    test('课名含空格：大学 英语 → 拼接为一个课名，末段教师消歧', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '大学 英语  张三  1-16周',
      );
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '大学 英语');
      expect(e.teacher, '张三');
      expect(e.weeks, {for (int i = 1; i <= 16; i++) i});
    });

    test('地点带空格：松山湖 松6-604 → 显示取楼栋', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '军事理论\n华康\n1-16周\n松山湖 松6-604',
      );
      expect(entries.single.location, '松6-604');
      expect(entries.single.name, '军事理论');
      expect(entries.single.teacher, '华康');
    });

    test('一格多课（两个周次段锚点切分）：各字段正确', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '军事理论\n张三\n11-14周\n松6-604\n高等数学\n李四\n1-16周\n教1-201',
      );
      expect(entries, hasLength(2));
      final GenericCellEntry first = entries[0];
      expect(first.name, '军事理论');
      expect(first.teacher, '张三');
      expect(first.weeks, <int>{11, 12, 13, 14});
      expect(first.location, '松6-604');
      final GenericCellEntry second = entries[1];
      expect(second.name, '高等数学');
      expect(second.teacher, '李四');
      expect(second.weeks, {for (int i = 1; i <= 16; i++) i});
      expect(second.location, '教1-201');
    });

    test('格内自带节次：第3-4节 在课名前', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '第3-4节 高等数学 1-16周',
      );
      expect(entries.single.name, '高等数学');
      expect(entries.single.sectionStart, 3);
      expect(entries.single.sectionEnd, 4);
      expect(entries.single.weeks, {for (int i = 1; i <= 16; i++) i});
    });

    test('裸节次段：高等数学 3-4节 1-16周', () {
      final List<GenericCellEntry> entries = parseGenericCell(
        '高等数学 3-4节 1-16周',
      );
      expect(entries.single.sectionStart, 3);
      expect(entries.single.sectionEnd, 4);
      expect(entries.single.weeks, {for (int i = 1; i <= 16; i++) i});
    });
  });

  group('第 3 层兜底', () {
    test('空 / 纯空白格 → 空列表', () {
      expect(parseGenericCell(''), isEmpty);
      expect(parseGenericCell('   '), isEmpty);
      expect(parseGenericCell(' \n\n '), isEmpty);
    });

    test('乱码：课名=原文，周次空，不抛', () {
      final List<GenericCellEntry> entries = parseGenericCell('???@@@###');
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.name, '???@@@###');
      expect(e.weeks, isEmpty);
      expect(e.sectionStart, isNull);
      expect(e.fallback, isFalse);
    });

    test('只有周次+地点（拿不到课名）→ 兜底条目', () {
      final List<GenericCellEntry> entries = parseGenericCell('1-16周\n教1-201');
      expect(entries, hasLength(1));
      final GenericCellEntry e = entries.single;
      expect(e.fallback, isTrue);
      // 兜底语义：课名=整格并空格，周次留空（调用方填全部周）
      expect(e.name, '1-16周 教1-201');
      expect(e.weeks, isEmpty);
      expect(e.sectionStart, isNull);
    });

    test('兜底课名截断 40 字', () {
      final String long = '某' * 60;
      final List<GenericCellEntry> entries = parseGenericCell(long);
      expect(entries.single.fallback, isFalse);
      // 纯长文本能当课名（name 候选），不截断——截断只作用于第 3 层
      expect(entries.single.name, long);

      // 第 3 层触发场景（无课名候选）下的截断：
      // 构造超长的「周次 地点」格
      final String longNoName = '${'1-2周 ' * 30}教1-201';
      final List<GenericCellEntry> fallback = parseGenericCell(longNoName);
      expect(fallback.single.fallback, isTrue);
      expect(fallback.single.name.length, 40);
    });
  });
}
