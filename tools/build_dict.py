"""Build the offline dictionary SQLite database from ECDICT CSV.

Usage:
    python tools/build_dict.py <ecdict.csv> <output.sqlite> [--full]

Default mode keeps a curated subset for mobile:
    - words with frequency ranking (frq/bnc) or exam tags (zk/gk/cet4/cet6/ky/toefl/gre/ielts)
    - words with an English definition

--full keeps every entry (very large output).
"""

import csv
import re
import shutil
import sqlite3
import sys

CJK_RE = re.compile(r'[\u4e00-\u9fff]+')


def cjk_bigrams(text: str) -> list[str]:
    grams: set[str] = set()
    for run in CJK_RE.findall(text):
        for i in range(len(run) - 1):
            grams.add(run[i:i + 2])
        if len(run) == 1:
            grams.add(run)
    return list(grams)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    full = '--full' in sys.argv
    if len(args) != 2:
        print(__doc__)
        sys.exit(1)

    csv_path, db_path = args[0], args[1]

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.executescript(
        """
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA cache_size=-64000;
        CREATE TABLE words(
            word        TEXT PRIMARY KEY,
            phonetic    TEXT,
            definition  TEXT,
            translation TEXT,
            pos         TEXT,
            tag         TEXT,
            bnc         INTEGER,
            frq         INTEGER,
            exchange    TEXT,
            detail      TEXT,
            audio       TEXT
        );
        CREATE TABLE zh_index(
            seg  TEXT NOT NULL,
            word TEXT NOT NULL,
            PRIMARY KEY(seg, word)
        ) WITHOUT ROWID;
        """
    )

    total = 0
    kept = 0
    zh_rows: list[tuple[str, str]] = []
    batch: list[tuple] = []

    with open(csv_path, encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader)  # header
        for row in reader:
            if len(row) < 11:
                continue
            total += 1
            word = row[0]
            translation = row[3].replace('\\n', '\n')
            definition = row[2]
            tag = row[6]
            bnc = int(row[8]) if row[8] else 0
            frq = int(row[9]) if row[9] else 0
            if not word or (not translation and not definition):
                continue
            if not full:
                core = frq > 0 or bnc > 0 or bool(tag)
                has_def = bool(definition)
                if not (core or has_def):
                    continue
            batch.append(
                (
                    word, row[1], definition, translation, row[4],
                    tag, bnc, frq, row[10], row[11], row[12],
                )
            )
            kept += 1
            for gram in cjk_bigrams(f'{translation} {definition} {row[4]}'):
                zh_rows.append((gram, word))
            if len(batch) >= 20000:
                cur.executemany(
                    'INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?)', batch
                )
                batch = []
            if len(zh_rows) >= 100000:
                cur.executemany(
                    'INSERT OR IGNORE INTO zh_index VALUES (?,?)', zh_rows
                )
                zh_rows = []

    if batch:
        cur.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?)', batch)
    if zh_rows:
        cur.executemany(
            'INSERT OR IGNORE INTO zh_index VALUES (?,?)', zh_rows
        )

    cur.execute('CREATE INDEX idx_zh_seg ON zh_index(seg)')
    conn.commit()
    conn.execute('VACUUM')
    conn.close()

    # Also produce the gzip bundle shipped in the repository (the raw SQLite
    # file exceeds GitHub's 100 MB per-file limit).
    import gzip
    with open(db_path, 'rb') as f_in, gzip.open(
        db_path + '.gz', 'wb', compresslevel=9
    ) as f_out:
        shutil.copyfileobj(f_in, f_out)

    print(f'rows: total={total} kept={kept}')


if __name__ == '__main__':
    main()
