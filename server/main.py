"""LangMe LLM proxy — a tiny FastAPI service on top of `claude -p --model haiku`.

Runs on my VPS next to an authenticated Claude Code CLI (subscription).
The mobile app calls it for AI features; everything else in the app is offline.

Design constraints:
- cheap model only (haiku), short prompts — save subscription quota;
- one request at a time (asyncio lock) -> 429 when busy;
- disk cache for cacheable endpoints (explain/examples);
- static token auth via X-Auth-Token header.
"""

import asyncio
import hashlib
import json
import os
import subprocess
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

TOKEN = os.environ.get("LANGME_TOKEN", "")
MODEL = os.environ.get("LANGME_MODEL", "haiku")
CLAUDE_BIN = os.environ.get("LANGME_CLAUDE_BIN", "claude")
TIMEOUT_S = int(os.environ.get("LANGME_TIMEOUT", "60"))
CACHE_DIR = Path(os.environ.get("LANGME_CACHE", "~/.cache/langme_llm")).expanduser()
CACHE_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="LangMe LLM proxy")
lock = asyncio.Lock()


def check_token(token: str | None):
    if not TOKEN:
        raise HTTPException(500, "LANGME_TOKEN is not configured on the server")
    if token != TOKEN:
        raise HTTPException(401, "bad token")


def cache_path(key: str) -> Path:
    return CACHE_DIR / (hashlib.sha256(key.encode()).hexdigest() + ".txt")


def run_claude(prompt: str) -> str:
    try:
        proc = subprocess.run(
            [CLAUDE_BIN, "-p", "--model", MODEL, prompt],
            capture_output=True,
            text=True,
            timeout=TIMEOUT_S,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "LLM timeout")
    except FileNotFoundError:
        raise HTTPException(500, f"claude CLI not found: {CLAUDE_BIN}")
    if proc.returncode != 0:
        raise HTTPException(502, f"claude failed: {proc.stderr.strip()[:300]}")
    text = proc.stdout.strip()
    if not text:
        raise HTTPException(502, "empty LLM response")
    return text


async def ask(prompt: str, cache_key: str | None = None) -> str:
    if cache_key:
        p = cache_path(cache_key)
        if p.exists():
            return p.read_text()
    if lock.locked():
        raise HTTPException(429, "busy, retry later")
    async with lock:
        text = await asyncio.to_thread(run_claude, prompt)
    if cache_key:
        cache_path(cache_key).write_text(text)
    return text


class WordReq(BaseModel):
    word: str
    ru: str = ""


class CheckReq(BaseModel):
    word: str
    sentence: str


class ChatReq(BaseModel):
    history: list[dict]
    recent_words: list[str] = []


@app.get("/health")
async def health(x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    return {"ok": True, "model": MODEL}


@app.post("/llm/explain")
async def explain(req: WordReq, x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    prompt = (
        f'Объясни английское слово "{req.word}" (перевод: {req.ru}) русскоязычному '
        "ученику ИНАЧЕ, чем словарём: простая ассоциация или мини-история для запоминания, "
        "типичные сочетания, чем отличается от похожих слов. До 6 коротких строк, без вступления."
    )
    return {"text": await ask(prompt, cache_key=f"explain:{req.word}")}


@app.post("/llm/examples")
async def examples(req: WordReq, x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    prompt = (
        f'Дай 4 новых примера с английским словом "{req.word}" (перевод: {req.ru}): '
        "разговорные, разные времена и контексты. Формат каждой строки: EN — RU. "
        "Только 4 строки, без вступления."
    )
    return {"text": await ask(prompt, cache_key=f"examples:{req.word}")}


class DialogReq(BaseModel):
    word: str
    ru: str = ""
    level: str = "A2"


@app.post("/llm/dialog")
async def dialog(req: DialogReq, x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    prompt = (
        f'Составь короткий естественный диалог из 4 реплик между говорящими A и B '
        f'(чередуются: A, B, A, B), где английское слово "{req.word}" '
        f"(перевод: {req.ru}) звучит минимум дважды. Сложность — уровень {req.level}. "
        'Ответ — ТОЛЬКО валидный JSON-массив без пояснений: '
        '[{"s":"A","en":"...","ru":"перевод"},{"s":"B","en":"...","ru":"..."},'
        '{"s":"A","en":"...","ru":"..."},{"s":"B","en":"...","ru":"..."}]'
    )
    return {"text": await ask(prompt, cache_key=f"dialog:{req.word}")}


@app.post("/llm/check")
async def check(req: CheckReq, x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    prompt = (
        f'Ученик тренирует слово "{req.word}" и написал предложение: "{req.sentence}". '
        "Проверь грамматику и естественность. Ответь по-русски максимум 4 строками: "
        "1) вердикт (верно / есть ошибки); 2) исправленный вариант, если нужно; "
        "3) одна короткая подсказка."
    )
    return {"text": await ask(prompt)}


@app.post("/llm/chat")
async def chat(req: ChatReq, x_auth_token: str | None = Header(default=None)):
    check_token(x_auth_token)
    dialog = "\n".join(
        f"{'Student' if m.get('role') == 'user' else 'Tutor'}: {m.get('text', '')}"
        for m in req.history[-12:]
    )
    words = ", ".join(req.recent_words[:15]) or "-"
    prompt = (
        "Ты дружелюбный репетитор английского для русскоязычного ученика. "
        "Отвечай коротко (2-4 предложения), в основном по-английски простыми словами, "
        "поправляй грубые ошибки одной строкой по-русски. "
        f"Старайся естественно вплетать недавние слова ученика: {words}.\n\n"
        f"Диалог:\n{dialog}\n\nTutor:"
    )
    return {"text": await ask(prompt)}
