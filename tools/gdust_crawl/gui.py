#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课表抓取工具 —— 图形界面版（傻瓜模式）。

为什么能做得这么简单：接口细节已经实测确认（见 README「已验证的接口事实」）：

    ① GET /app/zf/get_school_calendar?jobNumber=<学号>
       → 返回 { week, year, semester, allWeek }
       （学年、学期、总周数、当前周全都有了，用户不用填）

    ② GET /app/zf/get_student_course?jobNumber=&year=&semester=&week=
       → data.courseList 是课程数组

两者都只需要一个请求头：TOKEN（登录后存在浏览器 sessionStorage 里）。

所以用户只需要做两件事：
    1. 填学号
    2. 从浏览器复制 TOKEN（控制台一行命令，自动进剪贴板）

解析与聚合逻辑复用命令行版 crawl.py，保证两个入口行为一致。
"""

from __future__ import annotations

import json
import os
import random
import sys
import threading
import time
import tkinter as tk
import urllib.error
import urllib.request
import webbrowser
from tkinter import filedialog, messagebox, ttk

# 复用命令行版的解析与聚合逻辑（同名目录）
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from crawl import aggregate, collect_courses  # noqa: E402

BASE = 'https://portal.gdust.edu.cn/smart-admin-api'
API_CALENDAR = BASE + '/app/zf/get_school_calendar'
API_COURSE = BASE + '/app/zf/get_student_course'
PORTAL = 'https://portal.gdust.edu.cn/'

TOKEN_HINT = 'copy(sessionStorage.getItem("TOKEN"))'

USER_AGENT = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0 Safari/537.36'
)

# 模拟真实浏览器的请求头集合。
#
# 说明：**这不等于「隐身」** —— IP、TOKEN、访问模式该看见的都能看见。
# 这里只是避免「一眼就是裸脚本」这种最容易被 WAF 拦下的特征
# （只有 4 个头、没有 Accept-Language、没有 Sec-Fetch-*）。
BROWSER_HEADERS = {
    'User-Agent': USER_AGENT,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'identity',
    'Origin': 'https://portal.gdust.edu.cn',
    'Referer': PORTAL + 'home',
    'Sec-Fetch-Dest': 'empty',
    'Sec-Fetch-Mode': 'cors',
    'Sec-Fetch-Site': 'same-origin',
    'Sec-CH-UA': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
    'Sec-CH-UA-Mobile': '?0',
    'Sec-CH-UA-Platform': '"Windows"',
    'Connection': 'keep-alive',
}

# 周与周之间的随机间隔（秒）。固定间隔本身就是脚本特征，
# 随机化后与人工翻周的节奏更接近。
FETCH_DELAY_RANGE = (0.8, 2.2)


# ═══════════════════════════ 网络 ═══════════════════════════

def fetch_json(url: str, token: str, timeout: int = 20) -> tuple[dict, int]:
    """GET 一个接口，返回 (解析后的 JSON, HTTP 状态码)。

    教务接口在认证失败时也返回 HTTP 500 + JSON 体，所以即便非 200
    也要把 body 解析出来给上层判断。
    """
    request = urllib.request.Request(url, method='GET')
    request.add_header('TOKEN', token)
    for name, value in BROWSER_HEADERS.items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode('utf-8', errors='replace')
            status = response.status
    except urllib.error.HTTPError as error:
        body = error.read().decode('utf-8', errors='replace')
        status = error.code
    except urllib.error.URLError as error:
        return ({'_network_error': str(error.reason)}, 0)

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        payload = {'_raw': body[:500]}
    if not isinstance(payload, dict):
        payload = {'_raw': str(payload)[:500]}
    return (payload, status)


def describe_failure(payload: dict, status: int) -> str:
    """把失败响应翻译成一句人话。"""
    if status == 0:
        return '网络不通。校外访问需要校园网或学校 VPN。'
    if '_raw' in payload:
        return f'响应不是 JSON（HTTP {status}）：{payload["_raw"][:160]}'
    code = payload.get('code')
    msg = payload.get('msg') or payload.get('message') or ''
    # 116 = 未带 TOKEN / 认证失败；117 = 离线超时（实测假 TOKEN 返回这个）
    if code in (116, 117) or '认证失败' in str(msg) or '重新登录' in str(msg):
        reason = f'（服务端：{msg}）' if msg else ''
        return f'TOKEN 无效或已过期{reason}。请在浏览器重新登录教务系统，再重新复制 TOKEN。'
    if msg:
        return f'接口返回失败（code={code}）：{msg}'
    return f'接口返回失败（HTTP {status}，code={code}）'


# ═══════════════════════════ 界面 ═══════════════════════════

class CrawlerApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title('课表抓取工具')
        self.root.geometry('780x860')
        self.root.minsize(700, 760)

        self.running = False
        self.result: dict[str, list[dict]] = {}
        self._last_output: str | None = None

        self._build_style()
        self._build_ui()

    # ─────────── 样式 ───────────
    def _build_style(self) -> None:
        style = ttk.Style(self.root)
        try:
            style.theme_use('vista')
        except tk.TclError:
            pass
        style.configure('Title.TLabel', font=('Microsoft YaHei UI', 15, 'bold'))
        style.configure('Step.TLabel', font=('Microsoft YaHei UI', 10, 'bold'))
        style.configure('Hint.TLabel', foreground='#666666')
        style.configure('Go.TButton', font=('Microsoft YaHei UI', 11, 'bold'))

    # ─────────── 布局 ───────────
    def _build_ui(self) -> None:
        outer = ttk.Frame(self.root, padding=16)
        outer.pack(fill='both', expand=True)

        ttk.Label(outer, text='课表抓取工具', style='Title.TLabel').pack(anchor='w')
        ttk.Label(
            outer,
            text='从广东科技学院教务系统抓取课表，生成可直接导入 App 的 timetable.json',
            style='Hint.TLabel',
        ).pack(anchor='w', pady=(2, 12))

        self._build_step1(outer)
        self._build_step2(outer)
        self._build_run(outer)
        self._build_log(outer)
        self._build_footer(outer)

    def _section(self, parent: ttk.Frame) -> ttk.LabelFrame:
        frame = ttk.LabelFrame(parent, padding=10)
        frame.pack(fill='x', pady=(0, 10))
        return frame

    def _build_step1(self, parent: ttk.Frame) -> None:
        box = self._section(parent)
        ttk.Label(box, text='① 登录教务系统', style='Step.TLabel').pack(anchor='w')
        ttk.Label(
            box,
            text='点下面的按钮打开门户，用你的学号密码登录，进到「我的课表」页面。',
            style='Hint.TLabel',
        ).pack(anchor='w', pady=(2, 6))
        ttk.Button(box, text='打开教务系统门户', command=self._open_portal).pack(anchor='w')

    def _build_step2(self, parent: ttk.Frame) -> None:
        box = self._section(parent)
        ttk.Label(box, text='② 复制登录凭证 TOKEN', style='Step.TLabel').pack(anchor='w')
        ttk.Label(
            box,
            text='有两种方式，任选一种：',
            style='Hint.TLabel',
        ).pack(anchor='w', pady=(2, 6))

        # 方式 A：控制台一行命令
        row_a = ttk.Frame(box)
        row_a.pack(fill='x', pady=(0, 4))
        ttk.Label(row_a, text='方式 A（推荐）：').pack(side='left')
        ttk.Button(
            row_a,
            text='复制一行命令',
            command=self._copy_token_command,
        ).pack(side='left')
        ttk.Label(
            row_a,
            text='然后在浏览器 F12 → Console 粘贴回车',
            style='Hint.TLabel',
        ).pack(side='left', padx=(8, 0))

        hint = ttk.Entry(box)
        hint.insert(0, TOKEN_HINT)
        hint.configure(state='readonly')
        hint.pack(fill='x', pady=(0, 8))

        # 方式 B：从剪贴板读取
        row_b = ttk.Frame(box)
        row_b.pack(fill='x')
        ttk.Label(row_b, text='方式 B：').pack(side='left')
        ttk.Button(
            row_b,
            text='从剪贴板读取 TOKEN',
            command=self._read_clipboard,
        ).pack(side='left')
        ttk.Label(
            row_b,
            text='（如果你已经从别处复制了 TOKEN）',
            style='Hint.TLabel',
        ).pack(side='left', padx=(8, 0))

    def _build_run(self, parent: ttk.Frame) -> None:
        box = self._section(parent)
        ttk.Label(box, text='③ 填学号 → 开始抓取', style='Step.TLabel').pack(anchor='w')

        form = ttk.Frame(box)
        form.pack(fill='x', pady=(8, 6))

        ttk.Label(form, text='学号').grid(row=0, column=0, sticky='w', pady=4)
        self.entry_job = ttk.Entry(form, width=28)
        self.entry_job.grid(row=0, column=1, sticky='we', padx=(10, 0), pady=4)

        ttk.Label(form, text='TOKEN').grid(row=1, column=0, sticky='w', pady=4)
        self.entry_token = ttk.Entry(form, width=52, show='•')
        self.entry_token.grid(row=1, column=1, sticky='we', padx=(10, 0), pady=4)
        self.var_show_token = tk.BooleanVar(value=False)
        ttk.Checkbutton(
            form,
            text='显示',
            variable=self.var_show_token,
            command=self._toggle_token_visible,
        ).grid(row=1, column=2, padx=(8, 0))

        form.columnconfigure(1, weight=1)

        action = ttk.Frame(box)
        action.pack(fill='x', pady=(6, 0))
        self.btn_start = ttk.Button(
            action,
            text='开始抓取',
            style='Go.TButton',
            command=self._start,
        )
        self.btn_start.pack(side='left')
        self.btn_save = ttk.Button(
            action,
            text='保存为 timetable.json',
            command=self._save,
            state='disabled',
        )
        self.btn_save.pack(side='left', padx=(10, 0))

        self.progress = ttk.Progressbar(box, mode='determinate')
        self.progress.pack(fill='x', pady=(10, 0))
        self.var_status = tk.StringVar(value='等待开始')
        ttk.Label(box, textvariable=self.var_status, style='Hint.TLabel').pack(
            anchor='w', pady=(4, 0)
        )

    def _build_log(self, parent: ttk.Frame) -> None:
        box = ttk.LabelFrame(parent, text='运行日志', padding=8)
        box.pack(fill='both', expand=True, pady=(0, 10))

        self.text_log = tk.Text(box, height=9, wrap='word', state='disabled')
        scroll = ttk.Scrollbar(box, orient='vertical', command=self.text_log.yview)
        self.text_log.configure(yscrollcommand=scroll.set)
        self.text_log.pack(side='left', fill='both', expand=True)
        scroll.pack(side='right', fill='y')

    def _build_footer(self, parent: ttk.Frame) -> None:
        footer = ttk.Frame(parent)
        footer.pack(fill='x')
        ttk.Label(
            footer,
            text='数据只保存在本机；本工具不保存你的密码，TOKEN 仅用于本次请求。',
            style='Hint.TLabel',
        ).pack(side='left')

    # ─────────── 交互 ───────────
    def _open_portal(self) -> None:
        webbrowser.open(PORTAL)

    def _copy_token_command(self) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(TOKEN_HINT)
        self._log('已复制命令到剪贴板：')
        self._log(f'  {TOKEN_HINT}')
        self._log('接下来：浏览器 F12 → Console → 粘贴 → 回车，TOKEN 会自动进剪贴板。')
        self._log('然后点「从剪贴板读取 TOKEN」。')

    def _read_clipboard(self) -> None:
        try:
            value = self.root.clipboard_get().strip()
        except tk.TclError:
            messagebox.showwarning('剪贴板是空的', '请先在浏览器控制台执行复制命令。')
            return
        if not value:
            messagebox.showwarning('剪贴板是空的', '请先在浏览器控制台执行复制命令。')
            return
        # 允许用户直接粘贴 `"eyJ..."`（带引号）或裸 token
        value = value.strip('"').strip("'")
        self.entry_token.delete(0, 'end')
        self.entry_token.insert(0, value)
        self._log(f'已从剪贴板读取 TOKEN（{len(value)} 字符）')

    def _toggle_token_visible(self) -> None:
        self.entry_token.configure(show='' if self.var_show_token.get() else '•')

    # ─────────── 日志（线程安全） ───────────
    def _log(self, message: str) -> None:
        self.text_log.configure(state='normal')
        self.text_log.insert('end', message + '\n')
        self.text_log.see('end')
        self.text_log.configure(state='disabled')

    def _log_from_worker(self, message: str) -> None:
        self.root.after(0, self._log, message)

    def _set_status(self, text: str, current: int = 0, total: int = 0) -> None:
        def apply() -> None:
            self.var_status.set(text)
            if total > 0:
                self.progress.configure(maximum=total, value=current)
        self.root.after(0, apply)

    # ─────────── 抓取 ───────────
    def _start(self) -> None:
        if self.running:
            return
        job = self.entry_job.get().strip()
        token = self.entry_token.get().strip()
        if not job:
            messagebox.showwarning('缺少学号', '请填写学号。')
            return
        if not token:
            messagebox.showwarning(
                '缺少 TOKEN',
                '请先在浏览器里复制 TOKEN，再点「从剪贴板读取 TOKEN」。',
            )
            return

        self.running = True
        self.result = {}
        self._last_output = None
        self.btn_start.configure(state='disabled')
        self.btn_save.configure(state='disabled')
        self.text_log.configure(state='normal')
        self.text_log.delete('1.0', 'end')
        self.text_log.configure(state='disabled')
        self._log('开始抓取…')

        threading.Thread(
            target=self._worker, args=(job, token), daemon=True
        ).start()

    def _worker(self, job: str, token: str) -> None:
        try:
            self._run(job, token)
        except Exception as error:  # noqa: BLE001 —— 兜底，绝不让线程静默死掉
            self._log_from_worker(f'✗ 意外错误：{error}')
            self._set_status('失败')
        finally:
            self.root.after(0, self._finish)

    def _run(self, job: str, token: str) -> None:
        # ── 步骤 1：查学期日历（学年/学期/总周数全自动） ──
        self._set_status('正在查询学期信息…')
        self._log('① 查询学期信息（学年 / 学期 / 总周数）…')
        calendar, status = fetch_json(f'{API_CALENDAR}?jobNumber={job}', token)
        data = calendar.get('data')
        if not isinstance(data, dict):
            self._log_from_worker(f'✗ {describe_failure(calendar, status)}')
            self._set_status('查询学期失败')
            return

        year = str(data.get('year') or '').strip()
        semester = str(data.get('semester') or '').strip()
        total_weeks = data.get('allWeek')
        try:
            total_weeks = int(total_weeks)
        except (TypeError, ValueError):
            total_weeks = 0
        if total_weeks <= 0:
            total_weeks = 20
            self._log_from_worker('  总周数没拿到，按 20 周处理')
        self._log_from_worker(
            f'  学年 {year or "?"} · 学期 {semester or "?"} · 总周数 {total_weeks}'
        )
        if not year or not semester:
            self._log_from_worker('  ⚠️ 学年/学期没拿到，接口可能变了；仍尝试抓取')

        # ── 步骤 2：逐周抓课程 ──
        self._log_from_worker(f'② 开始抓取 1..{total_weeks} 周…')
        collected: list[tuple[int, dict]] = []
        failures = 0
        whole_semester = False

        for week in range(1, total_weeks + 1):
            self._set_status(f'抓取第 {week}/{total_weeks} 周…', week - 1, total_weeks)
            url = (
                f'{API_COURSE}?jobNumber={job}'
                f'&year={year}&semester={semester}&week={week}'
            )
            payload, http_status = fetch_json(url, token)

            if payload.get('data') is None:
                failures += 1
                self._log_from_worker(f'  ✗ 第 {week} 周：{describe_failure(payload, http_status)}')
                if failures >= 2 and not collected:
                    self._log_from_worker('  连续失败，停止。请检查 TOKEN 是否过期。')
                    return
                continue

            entries: list[dict] = []
            collect_courses(payload, entries)
            if not entries:
                self._log_from_worker(f'  · 第 {week} 周：无课程')
                continue

            for entry in entries:
                collected.append((week, entry))
            # 条目声称覆盖了哪些周
            covered: set[int] = set()
            for entry in entries:
                covered |= entry.get('_weeks') or set()
            span = ''
            if covered:
                low, high = min(covered), max(covered)
                span = f'第 {low} 周' if low == high else f'第 {low}-{high} 周'
            self._log_from_worker(
                f'  ✓ 第 {week} 周：{len(entries)} 条'
                + (f'（覆盖 {span}）' if span else '')
            )

            # 只有「条目覆盖了请求周之外的其他周」才说明接口一次返回整学期。
            # 反例：按周返回的接口，条目自带的 week 就等于请求周——
            # 这种情况不能提前结束，否则只拿到一周。
            if (covered - {week}) and not whole_semester:
                whole_semester = True
                self._log_from_worker(
                    f'    ↳ 条目覆盖多个周（{span}）→ 接口一次返回整学期，提前结束'
                )
                break

            # 只在真的要抓下一周时才等待（随机间隔，避免固定节奏）
            time.sleep(random.uniform(*FETCH_DELAY_RANGE))

        # ── 步骤 3：聚合 ──
        self._set_status('整理数据…')
        self.result = aggregate(collected)
        total = sum(len(v) for v in self.result.values())
        if total == 0:
            self._log_from_worker('✗ 没抓到任何课程。')
            self._log_from_worker('  常见原因：TOKEN 过期 / 选错学期 / 该学期没有课表')
            self._set_status('失败')
            return

        weeks = sorted(self.result, key=int)
        self._log_from_worker('')
        self._log_from_worker(f'✓ 完成：{len(weeks)} 周，共 {total} 条')
        self._log_from_worker(f'  周次范围 {weeks[0]} ~ {weeks[-1]}')
        if failures:
            self._log_from_worker(f'  ⚠️ {failures} 周抓取失败')
        self._log_from_worker('')
        self._log_from_worker('下一步：点「保存为 timetable.json」，再传到手机导入。')
        self._set_status(f'完成：{len(weeks)} 周 / {total} 条', total_weeks, total_weeks)

        # 自动弹保存对话框（用户点了开始就是想拿到文件）
        self.root.after(0, self._save)

    def _finish(self) -> None:
        self.running = False
        self.btn_start.configure(state='normal')
        if self.result:
            self.btn_save.configure(state='normal')

    # ─────────── 保存 ───────────
    def _save(self) -> None:
        if not self.result:
            messagebox.showinfo('还没有数据', '请先抓取。')
            return
        path = filedialog.asksaveasfilename(
            title='保存课表 JSON',
            defaultextension='.json',
            initialfile='timetable.json',
            filetypes=[('JSON 文件', '*.json'), ('所有文件', '*.*')],
        )
        if not path:
            return
        try:
            with open(path, 'w', encoding='utf-8') as handle:
                json.dump(self.result, handle, ensure_ascii=False, indent=2)
        except OSError as error:
            messagebox.showerror('保存失败', str(error))
            return
        self._log(f'已保存到：{path}')
        self._last_output = path
        if messagebox.askyesno(
            '保存成功',
            f'已保存到：\n{path}\n\n要打开所在文件夹吗？',
        ):
            try:
                os.startfile(os.path.dirname(path))  # type: ignore[attr-defined]
            except OSError:
                pass


def main() -> None:
    root = tk.Tk()
    CrawlerApp(root)
    root.mainloop()


if __name__ == '__main__':
    main()
