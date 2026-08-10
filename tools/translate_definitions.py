#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Batch-translate English definitions in the offline dictionary to Chinese.

Uses the OpenCode Go API (DeepSeek V4 Flash, OpenAI-compatible endpoint).

Usage:
    set OPENCODE_GO_API_KEY=<your go api key>
    python tools/translate_definitions.py --db assets/dict.sqlite [options]

Options:
    --workers N     concurrent workers (default 6)
    --batch N       definitions per request (default 20)
    --limit N       translate at most N words (for testing); 0 = all (default 0)
    --failed FILE   append failed words to this file (default tools/translate_failed.txt)
    --tsv FILE      dump all results to TSV at the end (default tools/definition_cn.tsv)

Resumable: progress is tracked per word (column definition_cn + translate_queue
status table). Stop at any time (Ctrl+C / kill), re-run to continue from where
it left off. Results are committed after every batch.
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

API_URL = "https://opencode.ai/zen/go/v1/chat/completions"
MODEL = "deepseek-v4-flash"
USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)

SYSTEM_PROMPT = (
    "你是专业词典释义翻译。输入是带编号的英文词典释义，每条以\"编号. \"开头。"
    "请把每条释义完整翻译成简洁、准确、地道的中文，保留词性标注（如 n.、v.、a.、vt.、prep. 等）。"
    "只输出一个 JSON 数组，每个元素是一个字符串，以对应的输入编号开头（例如 \"1. 翻译\"）。"
    "如果一条释义包含多个含义，可以输出多个带同一编号的数组元素。禁止使用 JSON 对象/字典。"
    "不要输出任何其它内容。"
)

USER_TEMPLATE = "请翻译以下 {n} 条词典释义（每条对应一个编号）：\n{items}"

_NUM_PREFIX = re.compile(r"^\s*\d+\.\s*")


def log(msg: str) -> None:
    print(f"[{datetime.now():%H:%M:%S}] {msg}", flush=True)


def parse_translations(content: str, expected: int) -> list[str]:
    """Parse the model reply into `expected` translations aligned by index.

    Tolerates the model splitting one definition into several entries/keys
    (they are merged again). Returns [] on failure.
    """
    if not content:
        return []
    text = content.strip()
    m = re.search(r"```(?:json)?\s*(.*?)\s*```", text, re.S)
    if m:
        text = m.group(1).strip()
    return _align(_extract_strings(text), expected)


def _extract_strings(text: str) -> list[str]:
    """Pull every translation string out of the reply, in order."""
    try:
        arr = json.loads(text)
        if isinstance(arr, list):
            return _flatten_items(arr)
        if isinstance(arr, dict):
            return [str(v) for v in arr.values() if isinstance(v, str)]
    except json.JSONDecodeError:
        pass
    m = re.search(r"\[.*\]", text, re.S)
    if m:
        try:
            arr = json.loads(m.group(0))
            if isinstance(arr, list):
                return _flatten_items(arr)
        except json.JSONDecodeError:
            pass
    return [l.strip() for l in text.splitlines() if l.strip()]


def _flatten_items(arr) -> list[str]:
    out: list[str] = []
    for it in arr:
        if isinstance(it, str):
            out.append(it)
        elif isinstance(it, dict):
            out.extend(v for v in it.values() if isinstance(v, str))
        elif isinstance(it, (int, float)):
            out.append(str(it))
        else:
            return []
    return out


def _align(strs: list[str], expected: int) -> list[str]:
    if not strs:
        return []
    if expected == 1:
        return [_clean("\n".join(s for s in strs if s.strip()))]
    # 1) every line carries an id
    ids: list[tuple[int | None, str]] = []
    for s in strs:
        mm = re.match(r"^\s*(\d+)\s*[\.:]\s*(.*)$", s, re.S)
        if mm:
            ids.append((int(mm.group(1)), mm.group(2)))
        else:
            ids.append((None, s))
    if all(i is not None for i, _ in ids):
        groups: dict[int, list[str]] = {}
        for i, t in ids:
            groups.setdefault(i, []).append(t)
        if all(i in groups for i in range(1, expected + 1)):
            return [
                _clean("\n".join(groups[i])) for i in range(1, expected + 1)
            ]
    # 2) only the first sense of each word is numbered; later senses keep the
    #    segment until the next numbered line (model's common output shape)
    segments: dict[int, list[str]] = {}
    cur: int | None = None
    for s in strs:
        mm = re.match(r"^\s*(\d+)\s*[\.:]\s*(.*)$", s, re.S)
        if mm:
            i = int(mm.group(1))
            if i not in segments:
                segments[i] = []
            cur = i
            segments[i].append(mm.group(2))
        elif cur is not None:
            segments[cur].append(s)
    if all(i in segments for i in range(1, expected + 1)):
        return [
            _clean("\n".join(segments[i])) for i in range(1, expected + 1)
        ]
    # 3) plain positional
    if len(strs) == expected:
        return [_clean(x) for x in strs]
    return []


def _clean(s: str) -> str:
    s = _NUM_PREFIX.sub("", s)
    return s.strip()


def _post(key: str, payload: dict, retries: int = 4) -> dict:
    """POST the payload with retries on transient network errors."""
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        API_URL, data=body,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    last: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, TimeoutError, ConnectionError,
                OSError) as e:
            last = e
            if attempt < retries - 1:
                time.sleep(3 * (attempt + 1))
    raise last if last else RuntimeError("request failed")


def api_call(key: str, texts: list[str], max_tokens: int):
    """Translate a batch. Returns (list[str], usage dict). Raises on HTTP/parse error."""
    items = "\n".join(f"{i}. {t}" for i, t in enumerate(texts, 1))
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user",
             "content": USER_TEMPLATE.format(n=len(texts), items=items)},
        ],
        "temperature": 0.1,
        "max_tokens": max_tokens,
        "reasoning_effort": "none",
    }
    data = _post(key, payload)
    content = data["choices"][0]["message"].get("content", "")
    usage = data.get("usage", {})
    parsed = parse_translations(content, len(texts))
    if len(parsed) != len(texts):
        raise ValueError(
            f"parsed {len(parsed)} != expected {len(texts)}; "
            f"content: {content[:400]!r}"
        )
    return parsed, usage


class Progress:
    def __init__(self, total: int):
        self.total = total
        self.done = 0
        self.failed = 0
        self.lock = threading.Lock()
        self.start = time.time()
        self.prompt_tokens = 0
        self.completion_tokens = 0
        self.requests = 0

    def add(self, done: int, failed: int, prompt: int, completion: int, reqs: int):
        with self.lock:
            self.done += done
            self.failed += failed
            self.prompt_tokens += prompt
            self.completion_tokens += completion
            self.requests += reqs

    def snapshot(self):
        with self.lock:
            return dict(total=self.total, done=self.done, failed=self.failed,
                        prompt_tokens=self.prompt_tokens,
                        completion_tokens=self.completion_tokens,
                        requests=self.requests, elapsed=time.time() - self.start)


def monitor(progress: Progress, stop: threading.Event):
    while not stop.is_set():
        time.sleep(20)
        s = progress.snapshot()
        processed = s["done"] + s["failed"]
        if processed == 0:
            continue
        rate = processed / s["elapsed"]
        remaining = (s["total"] - processed) / rate if rate > 0 else 0
        log(
            f"进度 {processed}/{s['total']} "
            f"({s['done']}完成, {s['failed']}失败) | "
            f"{rate:.1f}词/秒 | 剩余约 {remaining/60:.0f} 分钟 | "
            f"{s['requests']} 请求 | "
            f"tokens in={s['prompt_tokens']} out={s['completion_tokens']}"
        )


def main():
    ap = argparse.ArgumentParser(description="翻译英文释义为中文")
    ap.add_argument("--db", default="assets/dict.sqlite")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--batch", type=int, default=6)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--failed", default="tools/translate_failed.txt")
    ap.add_argument("--tsv", default="tools/definition_cn.tsv")
    args = ap.parse_args()

    key = os.environ.get("OPENCODE_GO_API_KEY") or os.environ.get("OPENCODE_GO_KEY")
    if not key:
        log("错误：未设置环境变量 OPENCODE_GO_API_KEY")
        sys.exit(1)

    conn = sqlite3.connect(args.db, check_same_thread=False, timeout=60)
    conn.execute("PRAGMA journal_mode=MEMORY")
    conn.execute("PRAGMA synchronous=OFF")
    conn.execute("PRAGMA busy_timeout=60000")

    cur = conn.execute("PRAGMA table_info(words)")
    cols = {r[1] for r in cur.fetchall()}
    if "definition_cn" not in cols:
        conn.execute("ALTER TABLE words ADD COLUMN definition_cn TEXT")
    conn.execute(
        """CREATE TABLE IF NOT EXISTS translate_queue(
               word TEXT PRIMARY KEY, status TEXT NOT NULL)"""
    )
    conn.execute("UPDATE translate_queue SET status='pending' WHERE status='working'")
    conn.execute(
        """INSERT OR IGNORE INTO translate_queue(word, status)
           SELECT word, 'pending' FROM words"""
    )
    conn.commit()

    cur = conn.execute(
        """SELECT COUNT(*)
           FROM translate_queue q JOIN words w ON w.word = q.word
           WHERE q.status IN ('pending','failed')
             AND w.definition IS NOT NULL AND TRIM(w.definition) != ''"""
    )
    todo = cur.fetchone()[0]

    if todo == 0:
        log("没有待翻译的词条（全部完成或空释义）。")
        conn.close()
        sys.exit(0)

    log(f"待翻译 {todo} 条。")

    stop = threading.Event()
    progress = Progress(todo)
    db_lock = threading.Lock()

    def claim(batch_size: int):
        with db_lock:
            rows = conn.execute(
                """SELECT q.word, w.definition
                   FROM translate_queue q JOIN words w ON w.word = q.word
                   WHERE q.status = 'pending'
                     AND w.definition IS NOT NULL AND TRIM(w.definition) != ''
                   ORDER BY CASE WHEN w.frq > 0 THEN w.frq ELSE 100000000 END ASC,
                            w.word ASC
                   LIMIT ?""",
                (batch_size,),
            ).fetchall()
            if not rows:
                return []
            words = [r[0] for r in rows]
            marks = ",".join("?" * len(words))
            conn.execute(
                f"UPDATE translate_queue SET status='working' WHERE word IN ({marks})",
                words,
            )
            conn.commit()
            return rows

    def write_results(results: dict, words: list[str]):
        done, failed = [], []
        with db_lock:
            for w in words:
                v = results.get(w)
                if v:
                    conn.execute(
                        "UPDATE words SET definition_cn=? WHERE word=?", (v, w))
                    conn.execute(
                        "UPDATE translate_queue SET status='done' WHERE word=?", (w,))
                    done.append(w)
                else:
                    conn.execute(
                        "UPDATE translate_queue SET status='failed' WHERE word=?", (w,))
                    failed.append(w)
            conn.commit()
        return done, failed

    def worker():
        while not stop.is_set():
            if args.limit and progress.snapshot()["done"] >= args.limit:
                return
            batch = claim(args.batch)
            if not batch:
                return
            words = [b[0] for b in batch]
            defs = [b[1] for b in batch]
            results: dict[str, str] = {}
            ok = False
            for attempt in range(3):
                try:
                    max_tokens = min(8192, 180 * len(defs) + 1024)
                    trans, usage = api_call(key, defs, max_tokens)
                    results = dict(zip(words, trans))
                    ok = True
                    progress.add(0, 0, usage.get("prompt_tokens", 0),
                                 usage.get("completion_tokens", 0), 1)
                    break
                except Exception as e:
                    log(f"批次失败(重试 {attempt+1}/3): {str(e)[:160]}")
                    time.sleep(2 * (attempt + 1) ** 2)
            if not ok:
                for w, d in zip(words, defs):
                    try:
                        t, usage = api_call(key, [d], 8192)
                        results[w] = t[0]
                        progress.add(0, 0, usage.get("prompt_tokens", 0),
                                     usage.get("completion_tokens", 0), 1)
                    except Exception as e:
                        log(f"单词 {w!r} 失败: {str(e)[:160]}")
                        results[w] = ""
                    time.sleep(0.2)
            done, failed = write_results(results, words)
            progress.add(len(done), len(failed), 0, 0, 0)
            if failed:
                with open(args.failed, "a", encoding="utf-8") as f:
                    for w in failed:
                        f.write(w + "\n")
            time.sleep(0.05)

    threads = [threading.Thread(target=worker, daemon=True)
               for _ in range(max(1, args.workers))]
    mon = threading.Thread(target=monitor, args=(progress, stop), daemon=True)
    mon.start()
    for t in threads:
        t.start()

    try:
        for t in threads:
            t.join()
    except KeyboardInterrupt:
        log("收到 Ctrl+C，正在停止（当前批次可能未写入，重跑会续传）……")
        stop.set()
        time.sleep(1)
    finally:
        with db_lock:
            conn.execute("UPDATE translate_queue SET status='pending' WHERE status IN ('working','failed')")
            conn.commit()

    s = progress.snapshot()
    log("=" * 60)
    log(f"完成: 成功 {s['done']} | 失败 {s['failed']} | 共 {s['total']}")
    log(f"耗时 {s['elapsed']/60:.1f} 分钟 | {s['requests']} 请求")
    if s["prompt_tokens"] or s["completion_tokens"]:
        in_tok = s["prompt_tokens"] / 1e6
        out_tok = s["completion_tokens"] / 1e6
        est = in_tok * 0.14 + out_tok * 0.28
        log(f"tokens in={s['prompt_tokens']:,} out={s['completion_tokens']:,} "
            f"预计成本 ${est:.2f}")

    try:
        n = conn.execute(
            "SELECT COUNT(*) FROM words WHERE definition_cn IS NOT NULL AND definition_cn != ''"
        ).fetchone()[0]
        with open(args.tsv, "w", encoding="utf-8") as f:
            f.write("word\tdefinition_cn\n")
            for r in conn.execute(
                """SELECT word, definition_cn FROM words
                   WHERE definition_cn IS NOT NULL AND definition_cn != ''
                   ORDER BY word"""
            ):
                f.write(f"{r[0]}\t{r[1]}\n")
        log(f"已导出 TSV: {args.tsv}（{n} 条）")
    except Exception as e:
        log(f"导出 TSV 失败: {e}")

    conn.close()


if __name__ == "__main__":
    main()
