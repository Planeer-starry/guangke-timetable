# -*- coding: utf-8 -*-
"""crawl.py 核心逻辑自测（不联网，用构造数据）。

验证：节次归一化 / 字段别名提取 / 周次参数探测与替换 / weeks 解析。
接口本身无法验证（需要真实账号），这里只覆盖纯逻辑。
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from crawl import (  # noqa: E402
    aggregate,
    apply_single_double,
    collect_courses,
    detect_week_param,
    normalize_sections,
    parse_entry_weeks,
    parse_weeks,
    replace_query_param,
)

failures = []


def check(desc, actual, expected):
    if actual == expected:
        print(f'  OK   {desc}: {actual!r}')
    else:
        print(f'  FAIL {desc}: 实际={actual!r} 期望={expected!r}')
        failures.append(desc)


print('=== 1. normalize_sections ===')
check('3-4', normalize_sections('3-4'), '3-4')
check('第3-4节', normalize_sections('第3-4节'), '3-4')
check('3~4', normalize_sections('3~4'), '3-4')
check('单节 3', normalize_sections('3'), '3-3')
check('单节 第3节', normalize_sections('第3节'), '3-3')
check('逗号 1,2', normalize_sections('1,2'), '1-2')
check('紧凑 0102', normalize_sections('0102'), '1-2')
check('紧凑 0304', normalize_sections('0304'), '3-4')
check('数组 [1,2]', normalize_sections([1, 2]), '1-2')
check('空串', normalize_sections(''), '')
check('None', normalize_sections(None), '')
check('乱码', normalize_sections('abc'), '')

print()
print('=== 2. collect_courses（正方风格对象）===')
zhengfang = {
    'code': 0,
    'data': {
        'courseList': [
            {'kcmc': '高等数学BⅠ', 'xm': '谌凤霞', 'cdmc': '松6-502',
             'xqj': 2, 'jcs': '7-8'},
            {'kcmc': '大学英语Ⅰ', 'xm': '刘璐璐', 'cdmc': '松L4-502',
             'xqj': '3', 'jcs': '0102'},
            {'kcmc': '大学体育Ⅰ', 'xm': '李大勇', 'cdmc': '田径场',
             'xqj': 4, 'jcs': [3, 4]},
        ]
    },
}
out = []
collect_courses(zhengfang, out)
print(f'  收集到 {len(out)} 条')
if len(out) == 3:
    print('  OK   数量 3')
else:
    print(f'  FAIL 数量应为 3，实际 {len(out)}')
    failures.append('正方数量')
check('第1条课名', out[0]['courseName'], '高等数学BⅠ')
check('第1条教师', out[0]['teacher'], '谌凤霞')
check('第1条地点', out[0]['classroomName'], '松6-502')
check('第1条星期', out[0]['dayWeek'], 2)
check('第1条节次', out[0]['whichSection'], '7-4' if False else '7-8')
check('第2条节次(紧凑)', out[1]['whichSection'], '1-2')
check('第2条星期(字符串)', out[1]['dayWeek'], 3)
check('第3条节次(数组)', out[2]['whichSection'], '3-4')

print()
print('=== 3. collect_courses（通用风格对象）===')
generic = {
    'rows': [
        {'courseName': '线性代数', 'teacherName': '王五',
         'classroom': '教1-201', 'day_of_week': 1, 'section': '5-6'},
    ]
}
out2 = []
collect_courses(generic, out2)
check('通用数量', len(out2), 1)
check('通用课名', out2[0]['courseName'] if out2 else None, '线性代数')
check('通用节次', out2[0]['whichSection'] if out2 else None, '5-6')

print()
print('=== 4. collect_courses（忽略非课程对象）===')
noise = {
    'code': 0,
    'msg': 'success',
    'data': {
        'total': 3,
        'student': {'name': '张三', 'jobNumber': '20260001'},
        'courseList': [
            {'kcmc': 'C语言程序设计C', 'xm': '苏华江', 'cdmc': '松L3-802',
             'xqj': 1, 'jcs': '9-10'},
        ],
    },
}
out3 = []
collect_courses(noise, out3)
check('噪音中只提取课程', len(out3), 1)
check('噪音中课名', out3[0]['courseName'] if out3 else None, 'C语言程序设计C')

print()
print('=== 5. detect_week_param ===')
url_full = 'https://portal.example.edu.cn/api/zf/get_student_course?jobNumber=20260001&year=2026&semester=1&week=5'
check('自动探测 week', detect_week_param(url_full, None), ('week', 5))
check('指定参数名', detect_week_param(url_full, 'week'), ('week', 5))
check('指定不存在的参数', detect_week_param(url_full, 'nope'), ('', None))
check('无查询串', detect_week_param('https://x.edu.cn/api/list', None), ('', None))
url_zc = 'https://x.edu.cn/api?zc=3&x=1'
check('探测 zc', detect_week_param(url_zc, None), ('zc', 3))

print()
print('=== 6. replace_query_param ===')
check('替换中间参数',
      replace_query_param(url_full, 'week', 12),
      'https://portal.example.edu.cn/api/zf/get_student_course?jobNumber=20260001&year=2026&semester=1&week=12')
check('替换末尾参数', replace_query_param(url_zc, 'zc', 9), 'https://x.edu.cn/api?zc=9&x=1')
check('追加参数', replace_query_param('https://x.edu.cn/api?a=1', 'week', 2),
      'https://x.edu.cn/api?a=1&week=2')
check('无查询串时追加', replace_query_param('https://x.edu.cn/api', 'week', 2),
      'https://x.edu.cn/api?week=2')

print()
print('=== 7. parse_weeks ===')
check('1-20', parse_weeks('1-20'), list(range(1, 21)))
check('1-8,10-16', parse_weeks('1-8,10-16'),
      list(range(1, 9)) + list(range(10, 17)))
check('单值 5', parse_weeks('5'), [5])
check('乱序去重', parse_weeks('3,1,3,2'), [1, 2, 3])

print()
print('=== 8. parse_entry_weeks（条目自带的周次字段）===')
check('数字 5', parse_entry_weeks(5), {5})
check('范围 1-16', parse_entry_weeks('1-16'), set(range(1, 17)))
check('带周字 1-16周', parse_entry_weeks('1-16周'), set(range(1, 17)))
check('列表 8,10,12', parse_entry_weeks('8,10,12'), {8, 10, 12})
check('数组 [1,2,3]', parse_entry_weeks([1, 2, 3]), {1, 2, 3})
check('None', parse_entry_weeks(None), set())
check('空串', parse_entry_weeks(''), set())

print()
print('=== 9. apply_single_double（单双周过滤）===')
check('双周', apply_single_double({1, 2, 3, 4}, '双'), {2, 4})
check('单周', apply_single_double({1, 2, 3, 4}, '单'), {1, 3})
check('编码 2=双周', apply_single_double({1, 2, 3, 4}, '2'), {2, 4})
check('无标记原样', apply_single_double({1, 2, 3}, None), {1, 2, 3})

print()
print('=== 10. collect_courses 捕获周次与单双周字段 ===')
zf = {'data': {'courseList': [
    {'courseName': '大学英语Ⅰ', 'teacherName': '刘璐璐', 'classroomName': '松4-405',
     'dayWeek': 2, 'whichSection': 1, 'week': '1-16', 'singleOrDoubleWeek': '双'},
]}}
out_zf = []
collect_courses(zf, out_zf)
check('数量', len(out_zf), 1)
check('_weeks', out_zf[0]['_weeks'], set(range(1, 17)))
check('_singleDouble', out_zf[0]['_singleDouble'], '双')
check('whichSection 数字 -> 区间串', out_zf[0]['whichSection'], '1-1')

print()
print('=== 11. aggregate：一次返回整学期（多次抓取不重复）===')
one = {'courseName': '高等数学BⅠ', 'teacher': '谌凤霞', 'classroomName': '松5-307',
       'dayWeek': 3, 'whichSection': '5-5', '_weeks': {7, 8}, '_singleDouble': ''}
agg = aggregate([(7, one), (8, one), (9, one)])
check('周键', sorted(agg.keys(), key=int), ['7', '8'])
check('每周条数', [len(v) for v in agg.values()], [1, 1])

print()
print('=== 12. aggregate：按周返回（条目无周次字段，用兜底周）===')
no_week = {'courseName': 'C语言程序设计C', 'teacher': '苏华江',
           'classroomName': '松L3-905', 'dayWeek': 4, 'whichSection': '7-7',
           '_weeks': set(), '_singleDouble': ''}
agg2 = aggregate([(7, no_week), (8, no_week)])
check('周键', sorted(agg2.keys(), key=int), ['7', '8'])
check('每周条数', [len(v) for v in agg2.values()], [1, 1])

print()
print('=== 13. aggregate：单双周过滤 ===')
sd = {'courseName': '大学英语Ⅰ', 'teacher': '刘璐璐', 'classroomName': '松4-405',
      'dayWeek': 2, 'whichSection': '1-1', '_weeks': {1, 2, 3, 4}, '_singleDouble': '双'}
agg3 = aggregate([(1, sd)])
check('双周只留偶数周', sorted(agg3.keys(), key=int), ['2', '4'])

print()
print('=== 14. aggregate：同周内按星期+节次排序 ===')
a = {'courseName': 'A', 'teacher': '', 'classroomName': '', 'dayWeek': 5,
     'whichSection': '1-1', '_weeks': {1}, '_singleDouble': ''}
b = {'courseName': 'B', 'teacher': '', 'classroomName': '', 'dayWeek': 1,
     'whichSection': '3-3', '_weeks': {1}, '_singleDouble': ''}
agg4 = aggregate([(1, a), (1, b)])
check('排序（周一在前）', [e['courseName'] for e in agg4['1']], ['B', 'A'])

print()
if failures:
    print(f'❌ 失败 {len(failures)} 项: {failures}')
    sys.exit(1)
print('✅ 全部通过')
