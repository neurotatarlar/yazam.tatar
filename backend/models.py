"""Model adapter interfaces and helpers."""

import asyncio
import hashlib
import uuid
from collections.abc import AsyncGenerator

from .settings import Settings


class ModelAdapter:
    """Abstract base for model backends."""

    name = "base"

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Return a fully corrected string."""
        raise NotImplementedError

    def correct_stream(self, text: str, lang: str, request_id: str) -> AsyncGenerator[str, None]:
        """Yield corrected text chunks."""
        raise NotImplementedError


class MockAdapter(ModelAdapter):
    """Deterministic adapter for local development."""

    name = "mock"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        """Normalize input without any model call."""
        return normalize(text)

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        """Yield normalized text in small chunks with delays."""
        corrected = await self.correct(text, lang, request_id)
        for chunk in chunk_text(corrected, 28):
            await asyncio.sleep(0.12)
            yield chunk


class PromptAdapter(ModelAdapter):
    """Adapter that tags output with a prompt version."""

    def __init__(self, prompt_version: str):
        self.prompt_version = prompt_version
        self.name = "prompt"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        """Normalize input and append the prompt version marker."""
        return f"{normalize(text)} [prompt:{self.prompt_version}]"

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        """Yield prompt-tagged output in chunks."""
        corrected = await self.correct(text, lang, request_id)
        for chunk in chunk_text(corrected, 28):
            await asyncio.sleep(0.12)
            yield chunk


class LocalAdapter(ModelAdapter):
    """Placeholder for a local model backend."""

    name = "local"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        """Normalize input and append a local-model marker."""
        return f"{normalize(text)} [local-model]"

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        """Yield local-model output in chunks."""
        corrected = await self.correct(text, lang, request_id)
        for chunk in chunk_text(corrected, 32):
            await asyncio.sleep(0.1)
            yield chunk


def build_adapter(settings: Settings) -> ModelAdapter:
    """Select a model adapter based on configuration."""
    backend = settings.model_backend.strip().lower()
    if backend == "gemini":
        from .gemini import GeminiAdapter

        return GeminiAdapter(settings.gemini_api_keys, settings.gemini_model)
    if backend == "prompt":
        return PromptAdapter(settings.prompt_version)
    if backend == "local":
        return LocalAdapter()
    return MockAdapter()


def normalize(text: str) -> str:
    """Collapse whitespace and capitalize the first character."""
    cleaned = " ".join(text.split()).strip()
    if not cleaned:
        return ""
    return cleaned[0].upper() + cleaned[1:]


def chunk_text(text: str, size: int):
    """Yield fixed-size chunks from a string."""
    for i in range(0, len(text), size):
        yield text[i : i + size]


def cache_key(text: str, lang: str) -> str:
    """Build a cache key from the input text and language."""
    return hashlib.sha256(f"{text}{lang}".encode()).hexdigest()


def request_id() -> str:
    """Generate a unique request identifier."""
    return uuid.uuid4().hex
