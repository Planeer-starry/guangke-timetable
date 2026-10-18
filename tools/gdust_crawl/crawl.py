#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""广科教务课表爬虫 —— 把教务系统的按周课程数据抓成 App 可导入的 JSON。

================================ 设计原则 ================================

本脚本【不硬编码】教务系统的接口细节（参数名、semester 编码、TOKEN 格式等），
因为那些值随学校/系统版本变化，猜错了就是白跑。

取而代之：你只需从浏览器 DevTools 里复制**一条已经能用的请求 URL**，
脚本把其中的周次参数当作模板，循环替换 weeks 1..N 抓取。

这样无论接口长什么样，都建立在「你亲眼见过它能返回数据」这个事实上。

================================ 用法 ================================

一、准备（只需要做一次）

  1. 浏览器打开教务系统并登录，进到「课表 / 我的课表」页面
  2. 按 F12 打开开发者工具 → Network（网络）标签
  3. 页面上切换一下周次（或者刷新），让它发出课程请求
  4. 在请求列表里找到返回课表数据的那个请求（响应里含课程名）
  5. 右键 → Copy → **Copy link address**（复制完整 URL）
  6. 右键 → Copy → **Copy as cURL**，从里面取出 Cookie 那一行
     （形如 Cookie: xxx=yyy; aaa=bbb）

二、运行

  python crawl.py --url "<复制的完整URL>" --cookie "<复制的Cookie>" --out 课表.json

  可选参数：
    --weeks 1-20        抓取范围（默认 1-20）
    --week-param week   周次参数在 URL 里的名字（默认自动探测）
    --school 广东科技学院 --semester "2026-2027年第1学期"
    --dump              把每周的原始响应也存下来（排查用）

三、导入

  把生成的 课表.json 传到手机，App → 设置 → 导入课表 → 从文件导入（.json）
  ⚠️ 导入后需要手动设置「第一周周一」（JSON 格式不含学期元信息）

================================ 输出格式 ================================

App 的 JSON 导入格式（按周展开）：

  {
    "1": [
      {"courseName": "高等数学BⅠ", "teacher": "谌凤霞",
       "classroomName": "松6-502", "dayWeek": 2, "whichSection": "7-8"}
    ],
    "2": [ ... ],
    ...
  }

================================ 免责 ================================

只读你自己的数据；不含登录逻辑、不保存账号密码。
请遵守学校的系统使用规范，不要高频请求。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request

# ───────────────────────── 字段别名表 ─────────────────────────
#
# 不同教务系统的字段名差异很大。这里按「优先级从高到低」列出常见写法：
#   正方 / 强智 / 青果 / URP 以及一些自研系统。
# 只要命中任意一个，就能提取出来。

NAME_KEYS = ['kcmc', 'courseName', 'course_name', 'name', 'kcmc_show']
TEACHER_KEYS = ['xm', 'teacher', 'teacherName', 'teacher_name', 'jsxm']
LOCATION_KEYS = ['cdmc', 'classroomName', 'classroom', 'room', 'jxdd', 'location', 'jsmc']
DAY_KEYS = ['xqj', 'dayWeek', 'day_of_week', 'day', 'dayOfWeek', 'week_day']
SECTION_KEYS = ['jcs', 'whichSection', 'section', 'jcor', 'sections', 'jc']
WEEK_TEXT_KEYS = ['zcd', 'weekText', 'weeks', 'zc', 'week_str']

# 形如 0102 / 0304 的紧凑节次编码（正方常见）：每两位一节
_COMPACT_SECTION = re.compile(r'^(?:\d{2})+$')


def _first_value(obj: dict, keys: list[str]):
    """按别名优先级取出第一个非空值。"""
    for key in keys:
        if key in obj and obj[key] not in (None, '', [], {}):
            return obj[key]
    return None


def _text(value) -> str:
    """把任意值转成修剪过的字符串。"""
    if value is None:
        return ''
    if isinstance(value, str):
        return value.strip()
    return str(value).strip()


def _to_int(value):
    """尽力把值转成 int；失败返回 None。"""
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    match = re.search(r'\d+', str(value))
    return int(match.group(0)) if match else None


def normalize_sections(raw) -> str:
    """把各种节次写法统一成 "3-4" 这样的区间字符串。

    支持：
      3-4 / 3~4 / 3—4 / 第3-4节   → "3-4"
      "1,2"                        → "1-2"
      "0102"（紧凑编码，每两位一节）  → "1-2"
      [1, 2]（数组）                → "1-2"
      3（单节）                     → "3-3"
    无法解析返回空串。
    """
    if raw is None:
        return ''
    if isinstance(raw, (list, tuple)):
        numbers = [n for n in (_to_int(item) for item in raw) if n]
        if not numbers:
            return ''
        return _span(numbers)

    text = _text(raw)
    if not text:
        return ''

    # 纯紧凑编码：0102 → 1,2
    if _COMPACT_SECTION.match(text):
        numbers = [int(text[i:i + 2]) for i in range(0, len(text), 2)]
        numbers = [n for n in numbers if n > 0]
        if numbers:
            return _span(numbers)

    # 去掉「第」「节」等修饰
    cleaned = text.replace('节', '').replace('第', '').strip()

    numbers = [int(n) for n in re.findall(r'\d+', cleaned)]
    if not numbers:
        return ''
    return _span(numbers)


def _span(numbers: list[int]) -> str:
    """把节次数字列表压成 "起-止"。"""
    low, high = min(numbers), max(numbers)
    return f'{low}-{high}'


def collect_courses(node, out: list[dict], depth: int = 0) -> None:
    """递归遍历响应 JSON，收集「像课程」的对象。

    判定标准：同时能取到「课程名」和「星期」。满足即认为是一条课程记录。
    这样不依赖响应外层结构（data / rows / courseList 都无所谓）。
    """
    if depth > 12:  # 防御异常深的响应
        return

    if isinstance(node, list):
        for item in node:
            collect_courses(item, out, depth + 1)
        return

    if not isinstance(node, dict):
        return

    name = _text(_first_value(node, NAME_KEYS))
    day = _to_int(_first_value(node, DAY_KEYS))
    if name and day is not None and 1 <= day <= 7:
        section = normalize_sections(_first_value(node, SECTION_KEYS))
        out.append({
            'courseName': name,
            'teacher': _text(_first_value(node, TEACHER_KEYS)),
            'classroomName': _text(_first_value(node, LOCATION_KEYS)),
            'dayWeek': day,
            'whichSection': section,
            'weekText': _text(_first_value(node, WEEK_TEXT_KEYS)),
        })
        # 课程对象内部一般不再嵌课程，收集完就返回
        return

    for value in node.values():
        collect_courses(value, out, depth + 1)


def detect_week_param(url: str, explicit: str | None) -> tuple[str, int | None]:
    """在 URL 的查询串里找「周次」参数。

    优先用 --week-param 指定的名字；否则按常见名猜测。
    返回 (参数名, 当前值)；找不到返回 ('', None)。
    """
    query = url.split('?', 1)[1] if '?' in url else ''
    if not query:
        return ('', None)

    # 解析成 名字 -> 值 的列表（保留重复键的可能性）
    pairs: list[tuple[str, str]] = []
    for part in query.split('&'):
        if '=' not in part:
            continue
        key, _, value = part.partition('=')
        pairs.append((key, value))

    if explicit:
        for key, value in pairs:
            if key == explicit:
                return (key, _to_int(value))
        return ('', None)

    for candidate in ('week', 'zc', 'weekNum', 'currentWeek', 'week_no'):
        for key, value in pairs:
            if key == candidate:
                return (key, _to_int(value))
    return ('', None)


def replace_query_param(url: str, name: str, value: int) -> str:
    """把 URL 查询串里 name 参数的值替换成 value（找不到则追加）。"""
    base, sep, query = url.partition('?')
    if not sep:
        return f'{base}?{name}={value}'

    parts = query.split('&')
    replaced = False
    for index, part in enumerate(parts):
        key = part.partition('=')[0]
        if key == name:
            parts[index] = f'{name}={value}'
            replaced = True
            break
    if not replaced:
        parts.append(f'{name}={value}')
    return f'{base}?{"&".join(parts)}'


def fetch(url: str, cookie: str, timeout: int = 20) -> tuple[str, int]:
    """发 GET 请求，返回 (响应文本, HTTP 状态码)。

    Cookie 通过命令行传入，不落盘、不打印。
    """
    request = urllib.request.Request(url, method='GET')
    request.add_header('Cookie', cookie)
    request.add_header('User-Agent',
                       'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                       'AppleWebKit/537.36 (KHTML, like Gecko) '
                       'Chrome/124.0 Safari/537.36')
    request.add_header('Accept', 'application/json, text/plain, */*')
    request.add_header('Referer', _origin_of(url))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace'), response.status
    except urllib.error.HTTPError as error:
        body = error.read().decode('utf-8', errors='replace')
        return body, error.code
    except urllib.error.URLError as error:
        return f'__NETWORK_ERROR__ {error.reason}', 0


def _origin_of(url: str) -> str:
    """取 URL 的 scheme://host 部分，作为 Referer。"""
    match = re.match(r'^(https?://[^/]+)', url)
    return match.group(1) + '/' if match else ''


def parse_weeks(spec: str) -> list[int]:
    """解析 --weeks 参数：支持 "1-20" 或 "1,3,5" 或 "1-8,10-16"。"""
    weeks: set[int] = set()
    for part in spec.split(','):
        part = part.strip()
        if not part:
            continue
        if '-' in part:
            low_text, _, high_text = part.partition('-')
            low, high = int(low_text), int(high_text)
            weeks.update(range(min(low, high), max(low, high) + 1))
        else:
            weeks.add(int(part))
    return sorted(weeks)


def main() -> int:
    parser = argparse.ArgumentParser(
        description='广科教务课表爬虫 —— 生成 App 可导入的 JSON',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--url', required=True,
                        help='从浏览器 DevTools 复制的一条可用请求 URL')
    parser.add_argument('--cookie', required=True,
                        help='该请求的 Cookie 请求头内容')
    parser.add_argument('--weeks', default='1-20', help='抓取范围，默认 1-20')
    parser.add_argument('--week-param', default=None,
                        help='周次参数名（默认自动探测）')
    parser.add_argument('--out', default='timetable.json', help='输出文件名')
    parser.add_argument('--delay', type=float, default=0.6,
                        help='每周请求间隔秒数，默认 0.6（请勿调得过低）')
    parser.add_argument('--dump', action='store_true',
                        help='把每周原始响应存到 raw/ 目录，便于排查')
    parser.add_argument('--timeout', type=int, default=20, help='单请求超时秒数')
    args = parser.parse_args()

    url = args.url.strip().strip('"').strip("'")
    cookie = args.cookie.strip().strip('"').strip("'")

    # 常见误操作：把整行 "Cookie: xxx" 粘进来了
    if cookie.lower().startswith('cookie:'):
        cookie = cookie[len('cookie:'):].strip()

    week_param, detected = detect_week_param(url, args.week_param)
    if not week_param:
        print('[✗] 没能从 URL 里找到周次参数。', file=sys.stderr)
        print('', file=sys.stderr)
        print('    当前 URL 的查询串里没有 week / zc 之类的键。', file=sys.stderr)
        print('    两种解决方式：', file=sys.stderr)
        print('      a) 用 --week-param 手动指定参数名，例如 --week-param week', file=sys.stderr)
        print('      b) 在浏览器里切换到真实的课表请求（URL 里应带周次），重新复制', file=sys.stderr)
        print('', file=sys.stderr)
        print(f'    你给的 URL: {url}', file=sys.stderr)
        return 2

    weeks = parse_weeks(args.weeks)
    print(f'[*] 周次参数: {week_param}（当前值 {detected}）')
    print(f'[*] 抓取范围: {weeks[0]}..{weeks[-1]}（共 {len(weeks)} 周）')

    result: dict[str, list[dict]] = {}
    seen_signature = None
    identical_weeks = 0
    failures: list[int] = []

    dump_dir = None
    if args.dump:
        import os
        dump_dir = os.path.join(os.getcwd(), 'raw')
        os.makedirs(dump_dir, exist_ok=True)
        print(f'[*] 原始响应将保存到: {dump_dir}')

    for index, week in enumerate(weeks, start=1):
        target = replace_query_param(url, week_param, week)
        text, status = fetch(target, cookie, args.timeout)

        if status == 0:
            print(f'[✗] 第 {week} 周：网络错误 —— {text}')
            failures.append(week)
            continue
        if status in (401, 403):
            print(f'[✗] 第 {week} 周：HTTP {status} —— Cookie 可能已过期，请重新登录后复制')
            failures.append(week)
            continue
        if status != 200:
            print(f'[✗] 第 {week} 周：HTTP {status}')
            failures.append(week)
            continue

        if dump_dir:
            with open(f'{dump_dir}/week{week:02d}.json', 'w', encoding='utf-8') as handle:
                handle.write(text)

        try:
            payload = json.loads(text)
        except json.JSONDecodeError:
            print(f'[✗] 第 {week} 周：响应不是 JSON（前 120 字）：{text[:120]}')
            failures.append(week)
            continue

        entries: list[dict] = []
        collect_courses(payload, entries)

        if not entries:
            print(f'[·] 第 {week} 周：无课程')
            result[str(week)] = []
        else:
            # 同周内去重（API 可能返回重复行）
            unique: list[dict] = []
            seen: set[tuple] = set()
            for entry in entries:
                key = (entry['courseName'], entry['teacher'], entry['classroomName'],
                       entry['dayWeek'], entry['whichSection'])
                if key not in seen:
                    seen.add(key)
                    unique.append(entry)
            result[str(week)] = [
                {k: v for k, v in entry.items() if k != 'weekText'}
                for entry in unique
            ]
            print(f'[✓] 第 {week} 周：{len(unique)} 条')

            # 检测「每周结果完全相同」——说明周次参数被接口忽略了
            signature = tuple(sorted(
                (e['courseName'], e['dayWeek'], e['whichSection']) for e in unique
            ))
            if seen_signature is None:
                seen_signature = signature
            elif signature == seen_signature:
                identical_weeks += 1

        if index < len(weeks):
            time.sleep(args.delay)

    if not any(result.values()):
        print('', file=sys.stderr)
        print('[✗] 所有周都没有抓到课程。常见原因：', file=sys.stderr)
        print('    · Cookie 失效 → 重新登录教务系统后重新复制', file=sys.stderr)
        print('    · 选错了请求 → 响应里应能看到课程名', file=sys.stderr)
        print('    · 需要校园网 / VPN → 校外访问内网地址会失败', file=sys.stderr)
        print(f'    · 加 --dump 重跑，查看 raw/ 里的原始响应', file=sys.stderr)
        return 1

    with open(args.out, 'w', encoding='utf-8') as handle:
        json.dump(result, handle, ensure_ascii=False, indent=2)

    total = sum(len(entries) for entries in result.values())
    print('')
    print(f'[✓] 已写出 {args.out}')
    print(f'    周数 {len(result)}，条目 {total}')
    if failures:
        print(f'    ⚠️ {len(failures)} 周失败：{failures}')
    if identical_weeks >= 3:
        print('')
        print('    ⚠️ 警告：多周结果完全相同，可能周次参数被接口忽略了。')
        print('       检查 --week-param 是否正确，或换个请求重新复制 URL。')
    print('')
    print('下一步：把该文件传到手机 → App → 设置 → 导入课表 → 从文件导入（.json）')
    print('        ⚠️ 导入后需手动设置「第一周周一」')
    return 0


if __name__ == '__main__':
    sys.exit(main())
