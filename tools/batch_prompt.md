# Промпт-шаблон батча для generate_words.sh

Скрипт подставляет `{LEVEL}`, `{COUNT}` и `{EXCLUDE}` и отдаёт это в
`claude -p --model haiku`:

```
Ты составляешь базу для приложения изучения английских слов русскоязычным учеником.
Выдай РОВНО {COUNT} английских слов уровня CEFR {LEVEL} — частотных и полезных в
повседневной жизни, работе и путешествиях. НЕ используй слова из этого списка
(они уже есть): {EXCLUDE}

Ответ — ТОЛЬКО валидный JSON-массив без markdown-ограждений и пояснений.
Каждый элемент:
{"word":"...","ipa":"/.../","pos":"noun|verb|adjective|adverb|preposition|phrase",
 "level":"{LEVEL}","ru":"перевод (кратко)","theme":"одна из: food, drink, travel,
 home, family, work, money, nature, animals, weather, body, health, clothes, city,
 transport, education, sport, art, music, technology, science, feelings, time,
 people, communication, law, business, other",
 "examples":[{"en":"пример 1","ru":"перевод"},{"en":"пример 2","ru":"перевод"}]}

Требования: примеры простые и разговорные, уровень примеров не выше {LEVEL};
перевод — самое употребимое значение; IPA британский или американский, любой.
```

Если батч возвращает битый JSON, скрипт автоматически повторяет запрос
(до 3 попыток), затем пропускает батч с предупреждением.
