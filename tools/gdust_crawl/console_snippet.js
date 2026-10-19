/**
 * 广科教务课表爬虫 —— 浏览器控制台版
 *
 * 相比 crawl.py 的优势：
 *   · 不需要导出/粘贴 Cookie —— 脚本在教务页面的上下文里运行，
 *     浏览器会自动带上登录态；
 *   · 不需要装 Python；
 *   · 跨域问题不存在（同源请求）。
 *
 * 使用方法：
 *   1. 浏览器登录教务系统，进到「课表」页面
 *   2. F12 → Network 标签 → 切换一次周次 → 找到返回课程数据的请求
 *   3. 右键该请求 → Copy → Copy link address（复制 URL）
 *   4. F12 → Console 标签 → 把本文件全部内容粘贴进去 → 回车
 *   5. 按提示粘贴刚才复制的 URL
 *   6. 自动下载 timetable.json
 *
 * 然后把 timetable.json 传到手机：
 *   App → 设置 → 导入课表 → 从文件导入（.json）
 *   ⚠️ 导入后需手动设置「第一周周一」
 *
 * 免责：只读取你自己的数据，不保存任何凭据。
 */

(async () => {
  'use strict';

  // ─────────── 字段别名（按优先级） ───────────
  const NAME_KEYS = ['kcmc', 'courseName', 'course_name', 'name', 'kcmc_show'];
  const TEACHER_KEYS = ['xm', 'teacher', 'teacherName', 'teacher_name', 'jsxm'];
  const LOCATION_KEYS = ['cdmc', 'classroomName', 'classroom', 'room', 'jxdd', 'location', 'jsmc'];
  const DAY_KEYS = ['xqj', 'dayWeek', 'day_of_week', 'day', 'dayOfWeek', 'week_day'];
  const SECTION_KEYS = ['jcs', 'whichSection', 'section', 'jcor', 'sections', 'jc'];
  const WEEK_KEYS = ['zcd', 'weekText', 'weeks', 'zc', 'week_str', 'week'];
  const SINGLE_DOUBLE_KEYS = ['singleOrDoubleWeek', 'singleOrDouble', 'single_or_double_week', 'weekType'];

  // ─────────── 工具函数 ───────────
  const text = (v) => (v === null || v === undefined ? '' : String(v).trim());

  const firstValue = (obj, keys) => {
    for (const key of keys) {
      if (key in obj) {
        const v = obj[key];
        if (v !== null && v !== undefined && v !== '' &&
            !(Array.isArray(v) && v.length === 0)) {
          return v;
        }
      }
    }
    return null;
  };

  const toInt = (v) => {
    if (v === null || v === undefined || typeof v === 'boolean') return null;
    if (typeof v === 'number') return Math.trunc(v);
    const m = String(v).match(/\d+/);
    return m ? parseInt(m[0], 10) : null;
  };

  /** 节次统一成 "3-4"。支持 3-4 / 第3-4节 / "1,2" / "0102" / [1,2] / 3 */
  const normalizeSections = (raw) => {
    if (raw === null || raw === undefined) return '';
    const span = (nums) => {
      const xs = nums.filter((n) => Number.isFinite(n) && n > 0);
      if (xs.length === 0) return '';
      return `${Math.min(...xs)}-${Math.max(...xs)}`;
    };
    if (Array.isArray(raw)) return span(raw.map(toInt).filter(Boolean));

    const s = text(raw);
    if (!s) return '';
    if (/^(?:\d{2})+$/.test(s)) {
      const nums = [];
      for (let i = 0; i < s.length; i += 2) nums.push(parseInt(s.slice(i, i + 2), 10));
      return span(nums);
    }
    const nums = (s.replace(/节|第/g, '').match(/\d+/g) || []).map((n) => parseInt(n, 10));
    return span(nums);
  };

  /** 条目自带的周次 → Set。支持 5 / "1-16" / "1-16周" / "8,10,12" / [1,2] */
  const parseEntryWeeks = (raw) => {
    const out = new Set();
    if (raw === null || raw === undefined) return out;
    if (Array.isArray(raw)) {
      raw.forEach((item) => parseEntryWeeks(item).forEach((w) => out.add(w)));
      return out;
    }
    if (typeof raw === 'number') {
      if (raw > 0) out.add(Math.trunc(raw));
      return out;
    }
    const s = text(raw).replace(/[周第（）()\[\]]/g, ' ');
    if (!s) return out;
    s.split(/[,，、;；\s]+/).forEach((part) => {
      if (!part) return;
      const rng = part.match(/^(\d+)\s*[-–~—到至]\s*(\d+)$/);
      if (rng) {
        const a = parseInt(rng[1], 10);
        const b = parseInt(rng[2], 10);
        for (let w = Math.min(a, b); w <= Math.max(a, b); w += 1) if (w > 0) out.add(w);
      } else if (/^\d+$/.test(part)) {
        const w = parseInt(part, 10);
        if (w > 0) out.add(w);
      }
    });
    return out;
  };

  /** 按 singleOrDoubleWeek 过滤单双周 */
  const applySingleDouble = (weeks, raw) => {
    const s = text(raw);
    if (!s) return weeks;
    const keepOdd = s.includes('单') || s === '1';
    const keepEven = s.includes('双') || s === '2';
    if (!keepOdd && !keepEven) return weeks;
    const out = new Set();
    weeks.forEach((w) => {
      if (keepOdd && w % 2 === 1) out.add(w);
      if (keepEven && w % 2 === 0) out.add(w);
    });
    return out;
  };

  /** 递归收集「同时有课程名和星期」的对象 */
  const collect = (node, out, depth = 0) => {
    if (depth > 12 || node === null || node === undefined) return;
    if (Array.isArray(node)) {
      node.forEach((item) => collect(item, out, depth + 1));
      return;
    }
    if (typeof node !== 'object') return;

    const name = text(firstValue(node, NAME_KEYS));
    const day = toInt(firstValue(node, DAY_KEYS));
    if (name && day !== null && day >= 1 && day <= 7) {
      out.push({
        courseName: name,
        teacher: text(firstValue(node, TEACHER_KEYS)),
        classroomName: text(firstValue(node, LOCATION_KEYS)),
        dayWeek: day,
        whichSection: normalizeSections(firstValue(node, SECTION_KEYS)),
        _weeks: parseEntryWeeks(firstValue(node, WEEK_KEYS)),
        _singleDouble: text(firstValue(node, SINGLE_DOUBLE_KEYS)),
      });
      return;
    }
    Object.values(node).forEach((v) => collect(v, out, depth + 1));
  };

  /** 两阶段聚合：按条目自带周次归组，无则用抓取时的周次；全量去重 */
  const aggregate = (collected) => {
    const buckets = {};
    const seen = new Set();
    collected.forEach(({ loopWeek, entry }) => {
      let weeks = entry._weeks && entry._weeks.size > 0
        ? entry._weeks
        : new Set([loopWeek]);
      weeks = applySingleDouble(weeks, entry._singleDouble);
      const clean = {
        courseName: entry.courseName,
        teacher: entry.teacher,
        classroomName: entry.classroomName,
        dayWeek: entry.dayWeek,
        whichSection: entry.whichSection,
      };
      [...weeks].sort((a, b) => a - b).forEach((w) => {
        const key = [w, clean.courseName, clean.teacher, clean.classroomName,
          clean.dayWeek, clean.whichSection].join('|');
        if (seen.has(key)) return;
        seen.add(key);
        (buckets[String(w)] = buckets[String(w)] || []).push(clean);
      });
    });
    const sectionKey = (s) => {
      const m = (s || '').match(/\d+/);
      return m ? parseInt(m[0], 10) : 999;
    };
    Object.keys(buckets).forEach((w) => {
      buckets[w].sort((a, b) =>
        a.dayWeek !== b.dayWeek ? a.dayWeek - b.dayWeek
          : sectionKey(a.whichSection) - sectionKey(b.whichSection));
    });
    return buckets;
  };

  /** 在查询串里找周次参数 */
  const detectWeekParam = (url) => {
    const q = url.includes('?') ? url.split('?')[1] : '';
    if (!q) return '';
    for (const cand of ['week', 'zc', 'weekNum', 'currentWeek', 'week_no']) {
      if (new RegExp(`(^|&)${cand}=`).test(q)) return cand;
    }
    return '';
  };

  const replaceParam = (url, name, value) => {
    const [base, query] = url.includes('?') ? [url.split('?')[0], url.split('?')[1]] : [url, ''];
    if (!query) return `${base}?${name}=${value}`;
    const parts = query.split('&');
    let hit = false;
    for (let i = 0; i < parts.length; i += 1) {
      if (parts[i].split('=')[0] === name) {
        parts[i] = `${name}=${value}`;
        hit = true;
        break;
      }
    }
    if (!hit) parts.push(`${name}=${value}`);
    return `${base}?${parts.join('&')}`;
  };

  // ─────────── 交互 ───────────
  const rawUrl = prompt(
    '把你在 DevTools → Network 里复制的「课表请求 URL」粘贴到这里：\n' +
    '（URL 里应包含周次参数，如 week=5 或 zc=5）'
  );
  if (!rawUrl) {
    console.warn('已取消。');
    return;
  }
  const url = rawUrl.trim();

  const weekParam = detectWeekParam(url);
  if (!weekParam) {
    console.error('❌ 这个 URL 里找不到周次参数（week / zc 等）。');
    console.error('   请在浏览器里切换到真实课表请求后重新复制。');
    console.error('   URL:', url);
    return;
  }

  const rangeText = prompt('抓取范围（默认 1-20）', '1-20') || '1-20';
  const weeks = [];
  rangeText.split(',').forEach((part) => {
    const p = part.trim();
    if (!p) return;
    if (p.includes('-')) {
      const [a, b] = p.split('-').map((n) => parseInt(n, 10));
      for (let i = Math.min(a, b); i <= Math.max(a, b); i += 1) weeks.push(i);
    } else {
      weeks.push(parseInt(p, 10));
    }
  });
  const weekList = [...new Set(weeks.filter((w) => Number.isFinite(w) && w > 0))]
    .sort((a, b) => a - b);

  console.log(`[*] 周次参数: ${weekParam}`);
  console.log(`[*] 抓取 ${weekList[0]}..${weekList[weekList.length - 1]}，共 ${weekList.length} 周`);

  // ─────────── 抓取 ───────────
  const collected = [];
  let failure = 0;
  let wholeSemester = false;

  for (const week of weekList) {
    const target = replaceParam(url, weekParam, week);
    let payload = null;
    try {
      const resp = await fetch(target, {
        credentials: 'include',
        headers: { Accept: 'application/json, text/plain, */*' },
      });
      if (!resp.ok) {
        console.warn(`[✗] 第 ${week} 周：HTTP ${resp.status}`);
        failure += 1;
        continue;
      }
      const body = await resp.text();
      try {
        payload = JSON.parse(body);
      } catch (e) {
        console.warn(`[✗] 第 ${week} 周：响应不是 JSON，前 120 字：${body.slice(0, 120)}`);
        failure += 1;
        continue;
      }
    } catch (e) {
      console.warn(`[✗] 第 ${week} 周：请求失败 ${e}`);
      failure += 1;
      continue;
    }

    const entries = [];
    collect(payload, entries);

    if (entries.length === 0) {
      console.log(`[·] 第 ${week} 周：无课程`);
    } else {
      entries.forEach((entry) => collected.push({ loopWeek: week, entry }));
      const withWeek = entries.filter((e) => e._weeks && e._weeks.size > 0).length;
      console.log(`[✓] 第 ${week} 周：${entries.length} 条`
        + (withWeek ? `（${withWeek} 条自带周次）` : ''));
      if (withWeek > 0 && !wholeSemester) {
        wholeSemester = true;
        console.log('    ↳ 条目自带 week 字段 → 判定为「一次返回整学期」，不再逐周抓取');
        break;
      }
    }
    await new Promise((r) => setTimeout(r, 500));
  }

  const result = aggregate(collected);
  const total = Object.values(result).reduce((sum, list) => sum + list.length, 0);
  if (total === 0) {
    console.error('❌ 所有周都没有抓到课程。');
    console.error('   常见原因：选错请求 / 登录态过期 / 需要校园网或 VPN。');
    return;
  }

  // ─────────── 下载 ───────────
  const blob = new Blob([JSON.stringify(result, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'timetable.json';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(a.href);

  const weekKeys = Object.keys(result).sort((x, y) => parseInt(x, 10) - parseInt(y, 10));
  console.log('─'.repeat(48));
  console.log('✅ 已下载 timetable.json');
  console.log(`   周数 ${weekKeys.length}（${weekKeys[0]}..${weekKeys[weekKeys.length - 1]}），条目 ${total}`);
  if (failure > 0) console.warn(`   ⚠️ ${failure} 周请求失败`);
  console.log('');
  console.log('下一步：传到手机 → App → 设置 → 导入课表 → 从文件导入（.json）');
  console.log('        ⚠️ 导入后需手动设置「第一周周一」');
  console.table(weekKeys.map((w) => ({ 周: w, 条数: result[w].length })));
})();
