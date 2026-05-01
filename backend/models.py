"""Adapter contracts and text utilities for correction backends."""

import hashlib
import logging
import uuid
from collections.abc import AsyncGenerator

from .settings import Settings


class ModelAdapter:
    """Abstract base for model backends."""

    name = "base"
    prefetch_first_chunk = False

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Return a fully corrected string."""
        raise NotImplementedError

    def correct_stream(self, text: str, lang: str, request_id: str) -> AsyncGenerator[str, None]:
        """Yield corrected text chunks."""
        raise NotImplementedError


class FallbackAdapter(ModelAdapter):
    """Primary adapter with secondary fallback for transient failures."""

    name = "fallback"
    prefetch_first_chunk = True

    def __init__(self, primary: ModelAdapter, fallback: ModelAdapter):
        self.primary = primary
        self.fallback = fallback
        self._logger = logging.getLogger("backend")

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Try primary adapter then fallback when upstream is retryable."""
        from .polza import PolzaRetryableError

        try:
            return await self.primary.correct(text, lang, request_id)
        except PolzaRetryableError as err:
            self._logger.warning(
                "upstream_fallback request_id=%s from=%s to=%s reason=%s status_code=%s code=%s",
                request_id,
                self.primary.name,
                self.fallback.name,
                err,
                err.status_code,
                err.code,
            )
            return await self.fallback.correct(text, lang, request_id)

    async def correct_stream(self, text: str, lang: str, request_id: str):
        """Try primary stream and fallback if it fails before first delta."""
        from .polza import PolzaRetryableError

        primary_stream = self.primary.correct_stream(text, lang, request_id)
        yielded = False
        try:
            async for chunk in primary_stream:
                yielded = True
                yield chunk
            return
        except PolzaRetryableError as err:
            if yielded:
                raise
            self._logger.warning(
                "upstream_fallback request_id=%s from=%s to=%s reason=%s status_code=%s code=%s",
                request_id,
                self.primary.name,
                self.fallback.name,
                err,
                err.status_code,
                err.code,
            )
            async for chunk in self.fallback.correct_stream(text, lang, request_id):
                yield chunk


def build_adapter(settings: Settings) -> ModelAdapter:
    """Select a model adapter based on configuration."""
    backend = settings.model_backend.strip().lower()
    if backend == "polza":
        from .gemini import GeminiAdapter
        from .polza import PolzaAdapter, PolzaProviderConfig

        primary = PolzaAdapter(
            api_key=settings.polza_api_key,
            model=settings.polza_model,
            base_url=settings.polza_base_url,
            timeout_seconds=settings.polza_timeout_seconds,
            provider=PolzaProviderConfig(
                allow_fallbacks=settings.polza_provider_allow_fallbacks,
                only=settings.polza_provider_only,
            ),
        )
        if settings.gemini_api_keys:
            return FallbackAdapter(
                primary, GeminiAdapter(settings.gemini_api_keys, settings.gemini_model)
            )
        logging.getLogger("backend").warning(
            "Polza backend is enabled without GEMINI_API_KEYS, direct fallback is unavailable."
        )
        return primary
    if backend == "gemini":
        from .gemini import GeminiAdapter

        return GeminiAdapter(settings.gemini_api_keys, settings.gemini_model)
    raise ValueError(f"Unsupported MODEL_BACKEND: {settings.model_backend}")


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


def cache_key(text: str) -> str:
    """Build a cache key from normalized correction input text."""
    return hashlib.sha256(text.encode()).hexdigest()


def request_id() -> str:
    """Generate a unique request identifier."""
    return uuid.uuid4().hex
