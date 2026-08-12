"""Build the offline dictionary SQLite database from ECDICT CSV.

Usage:
    python tools/build_dict.py <ecdict.csv> <output.sqlite> [--full]

Default mode keeps a curated subset for mobile:
    - words with frequency ranking (frq/bnc) or exam tags (zk/gk/cet4/cet6/ky/toefl/gre/ielts)
    - words with an English definition

--full keeps every entry (very large output).

A curated patch list (tools/patches.json, same directory as this script) is
merged into the result: existing words get extra Chinese senses prepended,
and words missing from ECDICT are inserted as new rows (tag='patch').
"""

import csv
import json
import os
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


def load_patches() -> dict[str, dict]:
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'patches.json')
    if not os.path.exists(path):
        print('no patches.json found, skipping patches')
        return {}
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    patches = {}
    for word, patch in data.items():
        if isinstance(patch, dict):
            patches[word.lower()] = patch
    print(f'patches: {len(patches)} words loaded from {path}')
    return patches


def merge_translation(existing: str, patched: str) -> str:
    """Prepend patched sense lines to the existing translation, deduping."""
    existing_lines = [l.strip() for l in existing.split('\n') if l.strip()]
    patched_lines = [l.strip() for l in patched.split('\n') if l.strip()]
    merged: list[str] = []
    seen: set[str] = set()
    for line in patched_lines + existing_lines:
        key = line.casefold()
        if key in seen:
            continue
        seen.add(key)
        merged.append(line)
    return '\n'.join(merged)


def load_definition_cn() -> dict[str, str]:
    """Loads the AI-generated Chinese WordNet glosses (word -> definition_cn).

    The TSV lives next to this script and is gitignored (huge, machine
    generated). Building without it simply leaves definition_cn empty.
    """
    path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), 'definition_cn.tsv'
    )
    if not os.path.exists(path):
        print('no definition_cn.tsv found, definition_cn will be empty')
        return {}
    result: dict[str, str] = {}
    with open(path, encoding='utf-8') as f:
        next(f, None)  # header
        for line in f:
            parts = line.rstrip('\n').split('\t', 1)
            if len(parts) == 2 and parts[1]:
                result[parts[0].lower()] = parts[1]
    print(f'definition_cn: {len(result)} glosses loaded')
    return result


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    full = '--full' in sys.argv
    if len(args) != 2:
        print(__doc__)
        sys.exit(1)

    csv_path, db_path = args[0], args[1]
    if os.path.exists(db_path):
        os.remove(db_path)
    if os.path.exists(db_path + '.gz'):
        os.remove(db_path + '.gz')
    patches = load_patches()
    definition_cn = load_definition_cn()

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
            audio       TEXT,
            definition_cn TEXT
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
    inserted: set[str] = set()
    with open(csv_path, encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader)  # header
        for row in reader:
            if len(row) < 11:
                continue
            total += 1
            word = row[0]
            patch = patches.get(word.lower())
            translation = row[3].replace('\\n', '\n')
            definition = row[2]
            tag = row[6]
            bnc = int(row[8]) if row[8] else 0
            frq = int(row[9]) if row[9] else 0
            if not word or (not translation and not definition):
                continue
            if not full:
                core = frq > 0 or bnc > 0 or bool(tag) or patch is not None
                has_def = bool(definition)
                if not (core or has_def):
                    continue
            if patch is not None:
                patched_tr = patch.get('translation')
                if patched_tr:
                    translation = merge_translation(translation, patched_tr)
            batch.append(
                (
                    word, row[1], definition, translation, row[4],
                    tag, bnc, frq, row[10], row[11], row[12],
                    definition_cn.get(word.lower(), ''),
                )
            )
            kept += 1
            inserted.add(word.lower())
            for gram in cjk_bigrams(f'{translation} {definition} {row[4]}'):
                zh_rows.append((gram, word))
            if len(batch) >= 20000:
                cur.executemany(
                    'INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', batch
                )
                batch = []
            if len(zh_rows) >= 100000:
                cur.executemany(
                    'INSERT OR IGNORE INTO zh_index VALUES (?,?)', zh_rows
                )
                zh_rows = []

    if batch:
        cur.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', batch)
    if zh_rows:
        cur.executemany(
            'INSERT OR IGNORE INTO zh_index VALUES (?,?)', zh_rows
        )

    # Insert words that exist only in the patch list (missing from ECDICT).
    patch_batch: list[tuple] = []
    for word, patch in patches.items():
        if word in inserted:
            continue
        translation = patch.get('translation', '').replace('\\n', '\n')
        definition = patch.get('definition', '')
        patch_batch.append(
            (
                word, '', definition, translation, '', 'patch', 0, 0,
                '', '', '', patch.get('definition_cn', ''),
            )
        )
        for gram in cjk_bigrams(f'{translation} {definition}'):
            zh_rows.append((gram, word))
    if patch_batch:
        cur.executemany('INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', patch_batch)
        kept += len(patch_batch)
        print(f'patched rows inserted: {len(patch_batch)}')
    if zh_rows:
        cur.executemany('INSERT OR IGNORE INTO zh_index VALUES (?,?)', zh_rows)

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
