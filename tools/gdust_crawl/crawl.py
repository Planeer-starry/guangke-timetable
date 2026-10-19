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
  ⚠️ 导入后需要手动设置「第一周周一」（本脚本不访问日历接口，输出不含
     学期元信息；gui.py 生成的文件自带 meta，导入时自动填写学期）

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
import datetime
import json
import random
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
WEEK_TEXT_KEYS = ['zcd', 'weekText', 'weeks', 'zc', 'week_str', 'week']
# 单双周标记（广科门户接口的 singleOrDoubleWeek，以及常见变体）
SINGLE_DOUBLE_KEYS = [
    'singleOrDoubleWeek',
    'singleOrDouble',
    'single_or_double_week',
    'weekType',
]

# 形如 0102 / 0304 的紧凑节次编码（正方常见）：每两位一节
_COMPACT_SECTION = re.compile(r'^(?:\d{2})+$')


def parse_entry_weeks(raw) -> set[int]:
    """把条目里的「周次」字段解析成周次集合。

    广科门户的 courseList 条目自带 `week` 字段，可能是：
      数字 5                → {5}
      字符串 "1-16" / "1-16周" → {1..16}
      字符串 "8,10,12"        → {8,10,12}
      数组 [1,2,3]           → {1,2,3}
    解析不出时返回空集合（调用方退回用抓取时的周次）。
    """
    if raw is None:
        return set()

    if isinstance(raw, (list, tuple)):
        weeks: set[int] = set()
        for item in raw:
            weeks |= parse_entry_weeks(item)
        return weeks

    if isinstance(raw, int) and not isinstance(raw, bool):
        return {raw} if raw > 0 else set()

    text = _text(raw)
    if not text:
        return set()

    # 去掉「周」「第」与括号，只留数字和分隔符
    cleaned = re.sub(r'[周第（）()\[\]]', ' ', text)
    weeks = set()
    for part in re.split(r'[,，、;；\s]+', cleaned):
        if not part:
            continue
        rng = re.match(r'^(\d+)\s*[-–~—到至]\s*(\d+)$', part)
        if rng:
            low, high = int(rng.group(1)), int(rng.group(2))
            weeks.update(range(min(low, high), max(low, high) + 1))
        elif re.match(r'^\d+$', part):
            value = int(part)
            if value > 0:
                weeks.add(value)
    return weeks


def apply_single_double(weeks: set[int], raw) -> set[int]:
    """按「单双周」标记过滤周次。

    singleOrDoubleWeek 可能是「单」「双」「1」「2」「单周」「双周」等写法；
    识别不出就原样返回。
    """
    if not weeks or raw is None:
        return weeks
    text = _text(raw)
    if not text:
        return weeks
    if '单' in text:
        return {w for w in weeks if w % 2 == 1}
    if '双' in text:
        return {w for w in weeks if w % 2 == 0}
    # 数字编码：1=单周 2=双周
    if text == '1':
        return {w for w in weeks if w % 2 == 1}
    if text == '2':
        return {w for w in weeks if w % 2 == 0}
    return weeks


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
        # 条目自带的周次与单双周标记：广科门户的 courseList 每个元素都带
        # `week` + `singleOrDoubleWeek`，前端在客户端过滤。带上它们，
        # 无论接口是「按周返回」还是「一次返回整学期」都能算对周次。
        week_raw = _first_value(node, WEEK_TEXT_KEYS)
        sd_raw = _first_value(node, SINGLE_DOUBLE_KEYS)
        out.append({
            'courseName': name,
            'teacher': _text(_first_value(node, TEACHER_KEYS)),
            'classroomName': _text(_first_value(node, LOCATION_KEYS)),
            'dayWeek': day,
            'whichSection': section,
            '_weeks': parse_entry_weeks(week_raw),
            '_singleDouble': _text(sd_raw),
        })
        # 课程对象内部一般不再嵌课程，收集完就返回
        return

    for value in node.values():
        collect_courses(value, out, depth + 1)


def section_sort_key(section: str) -> int:
    """节次字符串 -> 排序用数字（'3-4' -> 3；空 -> 999 排最后）。"""
    match = re.match(r'(\d+)', section or '')
    return int(match.group(1)) if match else 999


def aggregate(collected: list[tuple[int, dict]]) -> dict[str, list[dict]]:
    """把抓到的条目按周次归组，产出 App 可导入的 {"week": [entry, ...]}。

    归组规则：
    - 条目自带 `_weeks`（课程出现的周次集合）-> 按它归组，
      并用 `_singleDouble` 做单双周过滤；
    - 条目没有周次字段 -> 归到抓取它的那一周（按周返回的接口）。

    全量去重：接口若是「一次返回整学期」，每次抓取的条目完全相同，
    这里靠 (周, 课名, 教师, 地点, 星期, 节次) 只保留一份。
    """
    buckets: dict[str, list[dict]] = {}
    seen: set[tuple] = set()

    for loop_week, entry in collected:
        weeks = entry.get('_weeks') or {loop_week}
        weeks = apply_single_double(set(weeks), entry.get('_singleDouble'))
        clean = {k: v for k, v in entry.items() if not k.startswith('_')}
        for week in sorted(weeks):
            key = (
                week,
                clean['courseName'],
                clean['teacher'],
                clean['classroomName'],
                clean['dayWeek'],
                clean['whichSection'],
            )
            if key in seen:
                continue
            seen.add(key)
            buckets.setdefault(str(week), []).append(clean)

    for week in buckets:
        buckets[week].sort(
            key=lambda e: (e['dayWeek'], section_sort_key(e['whichSection']))
        )
    return buckets


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


# ───────────────────────── 学期元信息（J11） ─────────────────────────

def parse_start_date(raw) -> datetime.date | None:
    """把日历接口的 startTime 尽力解析成日期；失败返回 None。

    支持 date/datetime 对象、ISO 字符串（含带时间后缀）、
    YYYY/M/D、YYYY年M月D日 等写法。
    """
    if isinstance(raw, datetime.datetime):
        return raw.date()
    if isinstance(raw, datetime.date):
        return raw
    text = _text(raw)
    if not text:
        return None
    match = re.search(r'(\d{4})[-/年.](\d{1,2})[-/月.](\d{1,2})', text)
    if not match:
        return None
    try:
        return datetime.date(
            int(match.group(1)), int(match.group(2)), int(match.group(3))
        )
    except ValueError:  # 月份/日期越界（如 2026-13-40）
        return None


def semester_name_of(start_date) -> str:
    """从学期开始日推导学期名，如 "2026-2027年第1学期"。

    学年：8 月及以后开始 → 当年-次年（2026-08 → 2026-2027）；
          1~7 月开始 → 上一年-当年（2027-02 → 2026-2027）。
    学期：8~12 月开始 → 第 1 学期；1~7 月开始 → 第 2 学期。
    推导不出（没有可用日期）返回空串。
    """
    date = parse_start_date(start_date)
    if date is None:
        return ''
    if date.month >= 8:
        return f'{date.year}-{date.year + 1}年第1学期'
    return f'{date.year - 1}-{date.year}年第2学期'


def build_meta(start_time, total_weeks, school: str = '广东科技学院') -> dict | None:
    """从日历接口数据构建 App 导入 JSON 的顶层 meta；拿不到的绝不编造。

    - week1Monday：startTime 解析成日期后归一到所在周的周一（YYYY-MM-DD）；
    - semesterName：由学期开始日推导（best-effort，推不出就不写）；
    - totalWeeks：allWeek 能转成正整数才写（调用方回退用的默认值不算数）；
    - week1Monday 与 totalWeeks 一个都凑不出来时返回 None（整个 meta 省略）。
    """
    start = parse_start_date(start_time)
    weeks = _to_int(total_weeks)
    if start is None and not (weeks and weeks > 0):
        return None
    meta: dict = {'school': school}
    if start is not None:
        monday = start - datetime.timedelta(days=start.weekday())
        meta['week1Monday'] = monday.isoformat()
        name = semester_name_of(start)
        if name:
            meta['semesterName'] = name
    if weeks and weeks > 0:
        meta['totalWeeks'] = weeks
    return meta


def fetch(url: str, cookie: str, timeout: int = 20) -> tuple[str, int]:
    """发 GET 请求，返回 (响应文本, HTTP 状态码)。

    Cookie 通过命令行传入，不落盘、不打印。
    """
    request = urllib.request.Request(url, method='GET')
    request.add_header('Cookie', cookie)
    # 补齐真实浏览器会带的头。**这不等于隐身**（IP / 访问模式照样可见），
    # 只是避免「只有 3 个头」这种最容易触发 WAF 的裸脚本特征。
    for name, value in BROWSER_HEADERS.items():
        request.add_header(name, value)
    request.add_header('Referer', _origin_of(url))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read().decode('utf-8', errors='replace'), response.status
    except urllib.error.HTTPError as error:
        body = error.read().decode('utf-8', errors='replace')
        return body, error.code
    except urllib.error.URLError as error:
        return f'__NETWORK_ERROR__ {error.reason}', 0


# 模拟真实浏览器的请求头集合（理由见 fetch() 里的注释）
BROWSER_HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0 Safari/537.36'
    ),
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'identity',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-CH-UA': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'Sec-CH-UA-Mobile': '?0',
    'Sec-CH-UA-Platform': '"Windows"',
    'Connection': 'keep-alive',
}


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

    # 两阶段：先攒所有条目（带兜底周次），最后统一按条目自带周次归组。
    # 因为接口可能「一次返回整学期」（条目自带 week），也可能按周返回；
    # 两阶段能同时兼容，且跨批次重复会被去重。
    collected: list[tuple[int, dict]] = []
    whole_semester = False
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
        else:
            for entry in entries:
                collected.append((week, entry))
            covered: set[int] = set()
            for entry in entries:
                covered |= entry.get('_weeks') or set()
            span = ''
            if covered:
                low, high = min(covered), max(covered)
                span = f'第 {low} 周' if low == high else f'第 {low}-{high} 周'
            print(f'[✓] 第 {week} 周：{len(entries)} 条'
                  + (f'（覆盖 {span}）' if span else ''))
            # 只有条目覆盖了请求周之外的其他周，才判定为整学期返回
            if (covered - {week}) and not whole_semester:
                whole_semester = True
                print(f'    ↳ 条目覆盖多个周（{span}）→ 接口一次返回整学期，'
                      '不再逐周抓取')
                break

        if index < len(weeks):
            # 固定间隔本身是脚本特征，随机化到 1.0x ~ 2.5x
            time.sleep(random.uniform(args.delay, args.delay * 2.5))

    result = aggregate(collected)

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
    print('')
    print('下一步：把该文件传到手机 → App → 设置 → 导入课表 → 从文件导入（.json）')
    print('        ⚠️ 导入后需手动设置「第一周周一」')
    return 0


if __name__ == '__main__':
    sys.exit(main())
