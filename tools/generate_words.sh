#!/usr/bin/env bash
# Пополнение базы слов через подписку Claude Code: батчи по $BATCH слов на
# уровень через `claude -p --model haiku`. Запускать на сервере, где выполнен
# вход в claude. Пример:
#   ./tools/generate_words.sh A2 3     # 3 батча уровня A2
#   ./tools/generate_words.sh all 2    # по 2 батча каждого уровня A1..C1
set -euo pipefail

cd "$(dirname "$0")/.."
WORDS_JSON="app/assets/words.json"
BATCH="${BATCH:-100}"
MODEL="${MODEL:-haiku}"
LEVEL_ARG="${1:-all}"
ROUNDS="${2:-1}"

levels() {
  if [ "$LEVEL_ARG" = "all" ]; then echo "A1 A2 B1 B2 C1"; else echo "$LEVEL_ARG"; fi
}

gen_batch() {
  local level="$1"
  local exclude
  exclude=$(python3 - "$WORDS_JSON" <<'PY'
import json, sys
words = [w["word"] for w in json.load(open(sys.argv[1]))]
print(", ".join(words))
PY
)
  local prompt
  prompt=$(cat <<EOF
Ты составляешь базу для приложения изучения английских слов русскоязычным учеником.
Выдай РОВНО ${BATCH} английских слов уровня CEFR ${level} — частотных и полезных в повседневной жизни, работе и путешествиях. НЕ используй слова из этого списка (они уже есть): ${exclude}

Ответ — ТОЛЬКО валидный JSON-массив без markdown-ограждений и пояснений. Каждый элемент:
{"word":"...","ipa":"/.../","pos":"noun|verb|adjective|adverb|preposition|phrase","level":"${level}","ru":"перевод (кратко)","theme":"одна из: food, drink, travel, home, family, work, money, nature, animals, weather, body, health, clothes, city, transport, education, sport, art, music, technology, science, feelings, time, people, communication, law, business, other","examples":[{"en":"пример 1","ru":"перевод"},{"en":"пример 2","ru":"перевод"}]}

Требования: примеры простые и разговорные, уровень примеров не выше ${level}; перевод — самое употребимое значение; IPA любой (брит. или амер.).
EOF
)
  for attempt in 1 2 3; do
    echo "[$level] батч $BATCH слов, попытка $attempt..."
    if claude -p --model "$MODEL" "$prompt" > /tmp/langme_batch.txt 2>/tmp/langme_batch.err; then
      if python3 tools/validate_words.py /tmp/langme_batch.txt "$WORDS_JSON"; then
        return 0
      fi
      echo "[$level] батч не прошёл валидацию, повтор"
    else
      echo "[$level] claude -p упал: $(tail -1 /tmp/langme_batch.err)"; sleep 5
    fi
  done
  echo "[$level] ВНИМАНИЕ: батч пропущен после 3 попыток" >&2
  return 0
}

for level in $(levels); do
  for _ in $(seq 1 "$ROUNDS"); do
    gen_batch "$level"
  done
done

python3 - "$WORDS_JSON" <<'PY'
import json, sys
from collections import Counter
data = json.load(open(sys.argv[1]))
print(f"Итого в базе: {len(data)} слов", Counter(w["level"] for w in data))
PY
