"""Gemini-backed model adapter and key management."""

import asyncio
import threading
from collections.abc import AsyncGenerator, Awaitable, Callable

import google.generativeai as genai
from google.api_core import exceptions as google_exceptions

from .models import ModelAdapter


class GeminiKeyExhausted(Exception):
    """Raised when all configured Gemini API keys are exhausted."""

    pass


class GeminiKeyPool:
    """Round-robin key pool with exhaustion tracking."""

    def __init__(self, keys: list[str]):
        self._keys = [key.strip() for key in keys if key.strip()]
        self._exhausted: set[int] = set()
        self._current_index: int | None = None
        self._lock = asyncio.Lock()

    def has_keys(self) -> bool:
        """Return True if at least one key is configured."""
        return bool(self._keys)

    def key_count(self) -> int:
        """Return the total number of configured keys."""
        return len(self._keys)

    async def pick_key(self) -> str:
        """Pick the next available key or raise if all are exhausted."""
        async with self._lock:
            if not self._keys:
                raise GeminiKeyExhausted("No Gemini API keys configured.")

            index: int | None = self._current_index if self._current_index is not None else 0
            if index in self._exhausted:
                index = self._next_available_index(start=index + 1)

            if index is None:
                self._exhausted.clear()
                self._current_index = 0
                raise GeminiKeyExhausted(
                    "Gemini quota is exhausted for all keys. Please try again later."
                )

            self._current_index = index
            return self._keys[index]

    async def mark_exhausted(self, key: str) -> bool:
        """Mark a key as exhausted, returning True if all keys are exhausted."""
        async with self._lock:
            try:
                index = self._keys.index(key)
            except ValueError:
                return False
            self._exhausted.add(index)
            if len(self._exhausted) >= len(self._keys):
                self._exhausted.clear()
                self._current_index = 0
                return True
            if self._current_index == index:
                self._current_index = self._next_available_index(start=index + 1)
            return False

    def _next_available_index(self, start: int) -> int | None:
        """Find the next non-exhausted key index."""
        if not self._keys:
            return None
        for offset in range(len(self._keys)):
            index = (start + offset) % len(self._keys)
            if index not in self._exhausted:
                return index
        return None


class GeminiAdapter(ModelAdapter):
    """Model adapter that wraps the Google Gemini API."""

    name = "gemini"

    def __init__(self, keys: list[str], model: str):
        self._pool = GeminiKeyPool(keys)
        self._model = model
        self._configure_lock = threading.Lock()

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Return a corrected response using the first available key."""
        prompt = build_prompt(text, lang, request_id)

        async def call(key: str) -> str:
            return await asyncio.to_thread(self._generate_text, key, prompt)

        return await self._with_key(call)

    def correct_stream(self, text: str, lang: str, request_id: str) -> AsyncGenerator[str, None]:
        """Stream corrections from Gemini using SSE-friendly chunks."""
        prompt = build_prompt(text, lang, request_id)
        return self._stream_with_key(prompt)

    async def _with_key(self, func: Callable[[str], Awaitable[str]]) -> str:
        """Execute a request against the key pool with retries."""
        if not self._pool.has_keys():
            raise GeminiKeyExhausted("No Gemini API keys configured.")
        tried = 0
        while tried < self._pool.key_count():
            key = await self._pool.pick_key()
            try:
                return await func(key)
            except google_exceptions.ResourceExhausted as err:
                if await self._pool.mark_exhausted(key):
                    raise GeminiKeyExhausted(
                        "Gemini quota is exhausted for all keys. Please try again later."
                    ) from err
                tried += 1
            except google_exceptions.TooManyRequests as err:
                if await self._pool.mark_exhausted(key):
                    raise GeminiKeyExhausted(
                        "Gemini quota is exhausted for all keys. Please try again later."
                    ) from err
                tried += 1
        raise GeminiKeyExhausted("Gemini quota is exhausted for all keys. Please try again later.")

    async def _stream_with_key(self, prompt: str) -> AsyncGenerator[str, None]:
        """Stream responses while rotating keys on quota errors."""
        if not self._pool.has_keys():
            raise GeminiKeyExhausted("No Gemini API keys configured.")
        tried = 0
        yielded_any = False
        while tried < self._pool.key_count():
            key = await self._pool.pick_key()
            try:
                async for chunk in self._stream_once(key, prompt):
                    yielded_any = True
                    yield chunk
                return
            except google_exceptions.ResourceExhausted as err:
                exhausted_all = await self._pool.mark_exhausted(key)
                if yielded_any:
                    if exhausted_all:
                        raise GeminiKeyExhausted(
                            "Gemini quota is exhausted for all keys. Please try again later."
                        ) from err
                    raise
                if exhausted_all:
                    raise GeminiKeyExhausted(
                        "Gemini quota is exhausted for all keys. Please try again later."
                    ) from err
                tried += 1
            except google_exceptions.TooManyRequests as err:
                exhausted_all = await self._pool.mark_exhausted(key)
                if yielded_any:
                    if exhausted_all:
                        raise GeminiKeyExhausted(
                            "Gemini quota is exhausted for all keys. Please try again later."
                        ) from err
                    raise
                if exhausted_all:
                    raise GeminiKeyExhausted(
                        "Gemini quota is exhausted for all keys. Please try again later."
                    ) from err
                tried += 1
        raise GeminiKeyExhausted("Gemini quota is exhausted for all keys. Please try again later.")

    async def _stream_once(self, key: str, prompt: str) -> AsyncGenerator[str, None]:
        """Bridge the blocking Gemini streaming API into an async generator."""
        queue: asyncio.Queue[object] = asyncio.Queue()
        loop = asyncio.get_running_loop()

        def run():
            try:
                model = self._build_model(key)
                pieces: list[str] = []
                last_chunk = None
                for chunk in model.generate_content(prompt, stream=True):
                    last_chunk = chunk
                    text = _extract_text(chunk)
                    if text:
                        pieces.append(text)
                        loop.call_soon_threadsafe(queue.put_nowait, text)
                if not pieces:
                    fallback = _extract_text(last_chunk) if last_chunk is not None else None
                    if fallback:
                        loop.call_soon_threadsafe(queue.put_nowait, fallback)
                    else:
                        loop.call_soon_threadsafe(
                            queue.put_nowait, RuntimeError("Gemini returned empty response.")
                        )
                loop.call_soon_threadsafe(queue.put_nowait, None)
            except Exception as err:  # noqa: BLE001
                loop.call_soon_threadsafe(queue.put_nowait, err)

        thread = threading.Thread(target=run, daemon=True)
        thread.start()

        while True:
            item = await queue.get()
            if item is None:
                break
            if isinstance(item, Exception):
                raise item
            if not isinstance(item, str):
                raise RuntimeError("Unexpected stream item type.")
            yield item

    def _generate_text(self, key: str, prompt: str) -> str:
        """Call the Gemini API once and return plain text."""
        model = self._build_model(key)
        response = model.generate_content(prompt)
        text = _extract_text(response)
        if text:
            return text
        raise RuntimeError("Gemini returned empty response.")

    def _build_model(self, key: str):
        """Configure the SDK with the provided key and build a model."""
        with self._configure_lock:
            genai.configure(api_key=key)
            return genai.GenerativeModel(self._model)


def build_prompt(text: str, lang: str, request_id: str) -> str:
    """Create the instruction prompt for Gemini."""
    return (
        "You are a grammar and spelling correction assistant for Tatar text.\n"
        "Return only the corrected text. Do not add explanations or extra formatting.\n"
        "Preserve punctuation, line breaks, and the original meaning.\n"
        "Preserve the original casing unless a correction requires changing it.\n"
        f"Language: {lang}\n"
        f"Request-ID: {request_id}\n\n"
        f"Text:\n{text}"
    )


def _extract_text(response) -> str | None:
    """Extract text from the various Gemini response shapes."""
    text = getattr(response, "text", None)
    if text:
        return text
    candidates = getattr(response, "candidates", None)
    if not candidates:
        return None
    first = candidates[0] if candidates else None
    content = getattr(first, "content", None)
    parts = getattr(content, "parts", None) if content else None
    if not parts:
        return None
    collected = []
    for part in parts:
        value = getattr(part, "text", None)
        if value:
            collected.append(value)
    return "".join(collected) if collected else None
