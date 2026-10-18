# -*- coding: utf-8 -*-
"""crawl.py 核心逻辑自测（不联网，用构造数据）。

验证：节次归一化 / 字段别名提取 / 周次参数探测与替换 / weeks 解析。
接口本身无法验证（需要真实账号），这里只覆盖纯逻辑。
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from crawl import (  # noqa: E402
    collect_courses,
    detect_week_param,
    normalize_sections,
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
if failures:
    print(f'❌ 失败 {len(failures)} 项: {failures}')
    sys.exit(1)
print('✅ 全部通过')
