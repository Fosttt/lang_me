#!/usr/bin/env python3
"""Generate a 4-line mini-dialogue for every word in words.json.

Uses the Claude Code subscription (`claude -p --model haiku`) in batches,
writes back incrementally, so it is safe to interrupt and re-run — only
words without a "dialog" field are processed.

Usage: python3 tools/generate_dialogs.py [batch_size]
"""

import json
import re
import subprocess
import sys
from pathlib import Path

WORDS = Path(__file__).resolve().parent.parent / "app" / "assets" / "words.json"
BATCH = int(sys.argv[1]) if len(sys.argv) > 1 else 20
MODEL = "haiku"

PROMPT = """Для каждого английского слова из списка составь короткий естественный диалог из 4 реплик между говорящими A и B (строго чередуются: A, B, A, B), в котором это слово звучит минимум дважды. Сложность языка — соответствует уровню слова (указан в скобках). Диалоги бытовые и живые, перевод на русский разговорный.

Слова: {words}

Ответ — ТОЛЬКО валидный JSON-объект без markdown-ограждений, ключ — слово, значение — массив из 4 объектов:
{{"слово": [{{"s":"A","en":"реплика","ru":"перевод"}}, {{"s":"B","en":"...","ru":"..."}}, {{"s":"A","en":"...","ru":"..."}}, {{"s":"B","en":"...","ru":"..."}}], ...}}"""


def valid_dialog(d) -> bool:
    if not isinstance(d, list) or not (3 <= len(d) <= 6):
        return False
    for line in d:
        if not isinstance(line, dict):
            return False
        if line.get("s") not in ("A", "B"):
            return False
        if not line.get("en") or not line.get("ru"):
            return False
    return True


def run_batch(items) -> dict:
    listing = ", ".join(f"{w['word']} ({w['level']})" for w in items)
    prompt = PROMPT.format(words=listing)
    for attempt in range(1, 4):
        try:
            proc = subprocess.run(
                ["claude", "-p", "--model", MODEL, prompt],
                capture_output=True, text=True, timeout=300,
            )
        except subprocess.TimeoutExpired:
            print(f"  attempt {attempt}: timeout", flush=True)
            continue
        raw = proc.stdout.strip()
        raw = re.sub(r"^```[a-z]*\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)
        start, end = raw.find("{"), raw.rfind("}")
        if start < 0 or end <= start:
            print(f"  attempt {attempt}: no JSON", flush=True)
            continue
        try:
            data = json.loads(raw[start:end + 1])
        except json.JSONDecodeError as e:
            print(f"  attempt {attempt}: bad JSON ({e})", flush=True)
            continue
        good = {k: v for k, v in data.items() if valid_dialog(v)}
        if good:
            return good
        print(f"  attempt {attempt}: no valid dialogs", flush=True)
    return {}


def main():
    words = json.loads(WORDS.read_text())
    todo = [w for w in words if not w.get("dialog")]
    print(f"words without dialog: {len(todo)}", flush=True)
    by_word = {w["word"]: w for w in words}

    for i in range(0, len(todo), BATCH):
        chunk = todo[i:i + BATCH]
        print(f"batch {i // BATCH + 1}: {chunk[0]['word']}..{chunk[-1]['word']}",
              flush=True)
        result = run_batch(chunk)
        for word, dialog in result.items():
            key = word.strip()
            if key in by_word:
                by_word[key]["dialog"] = [
                    {"s": l["s"], "en": str(l["en"]).strip(),
                     "ru": str(l["ru"]).strip()}
                    for l in dialog
                ]
        WORDS.write_text(json.dumps(words, ensure_ascii=False, indent=0))
        done = sum(1 for w in words if w.get("dialog"))
        print(f"  merged {len(result)}; total with dialog: {done}/{len(words)}",
              flush=True)

    missing = [w["word"] for w in words if not w.get("dialog")]
    if missing:
        print(f"still missing ({len(missing)}): {', '.join(missing[:20])}...")
    else:
        print("all words have dialogs")


if __name__ == "__main__":
    main()
