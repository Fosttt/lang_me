#!/usr/bin/env python3
"""Validate an LLM batch and merge it into words.json.

Usage: validate_words.py <batch.txt> <words.json>
Exit 0 = merged OK, exit 1 = broken batch (caller retries).

Tolerates markdown fences around the JSON; drops entries that duplicate
existing words or miss required fields.
"""

import json
import re
import sys

REQUIRED = ("word", "ru", "level")


def main() -> int:
    batch_path, words_path = sys.argv[1], sys.argv[2]
    raw = open(batch_path).read().strip()
    # срезаем возможные ```json ... ``` ограждения
    raw = re.sub(r"^```[a-z]*\s*", "", raw)
    raw = re.sub(r"\s*```$", "", raw)
    # берём внешний массив, даже если вокруг есть текст
    start, end = raw.find("["), raw.rfind("]")
    if start < 0 or end <= start:
        print("validate: no JSON array found", file=sys.stderr)
        return 1
    try:
        batch = json.loads(raw[start : end + 1])
    except json.JSONDecodeError as e:
        print(f"validate: bad JSON: {e}", file=sys.stderr)
        return 1
    if not isinstance(batch, list) or not batch:
        print("validate: empty batch", file=sys.stderr)
        return 1

    words = json.load(open(words_path))
    existing = {w["word"].lower() for w in words}

    added = 0
    for item in batch:
        if not isinstance(item, dict):
            continue
        if any(not item.get(k) for k in REQUIRED):
            continue
        key = str(item["word"]).strip().lower()
        if key in existing:
            continue
        entry = {
            "word": str(item["word"]).strip(),
            "ipa": str(item.get("ipa", "")).strip(),
            "pos": str(item.get("pos", "")).strip(),
            "level": str(item["level"]).strip(),
            "ru": str(item["ru"]).strip(),
            "theme": str(item.get("theme", "other")).strip() or "other",
            "examples": [
                {"en": str(e.get("en", "")), "ru": str(e.get("ru", ""))}
                for e in item.get("examples", [])
                if isinstance(e, dict) and e.get("en")
            ],
        }
        words.append(entry)
        existing.add(key)
        added += 1

    if added == 0:
        print("validate: nothing new in batch", file=sys.stderr)
        return 1

    json.dump(words, open(words_path, "w"), ensure_ascii=False, indent=0)
    print(f"validate: merged {added} new words (total {len(words)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
