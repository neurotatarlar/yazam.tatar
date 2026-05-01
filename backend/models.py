"""Adapter contracts and text utilities for correction backends."""

import hashlib
import logging
import uuid
from collections.abc import AsyncGenerator
from contextvars import ContextVar

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
        self._backend_used: ContextVar[str | None] = ContextVar(
            f"fallback_backend_used_{id(self)}", default=None
        )

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Try primary adapter then fallback when upstream is retryable."""
        from .polza import PolzaRetryableError

        try:
            corrected = await self.primary.correct(text, lang, request_id)
            self._backend_used.set(backend_name(self.primary))
            return corrected
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
            corrected = await self.fallback.correct(text, lang, request_id)
            self._backend_used.set(backend_name(self.fallback))
            return corrected

    async def correct_stream(self, text: str, lang: str, request_id: str):
        """Try primary stream and fallback if it fails before first delta."""
        from .polza import PolzaRetryableError

        primary_stream = self.primary.correct_stream(text, lang, request_id)
        yielded = False
        try:
            async for chunk in primary_stream:
                if not yielded:
                    self._backend_used.set(backend_name(self.primary))
                yielded = True
                yield chunk
            if not yielded:
                self._backend_used.set(backend_name(self.primary))
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
                if not yielded:
                    self._backend_used.set(backend_name(self.fallback))
                yield chunk
                yielded = True
            if not yielded:
                self._backend_used.set(backend_name(self.fallback))

    def backend_used(self) -> str | None:
        """Return the backend selected for the current request context."""
        return self._backend_used.get()


def backend_name(adapter: ModelAdapter) -> str:
    """Return the actual backend used by an adapter for the current request."""
    backend_used = getattr(adapter, "backend_used", None)
    if callable(backend_used):
        selected = backend_used()
        if selected:
            return str(selected)
    return adapter.name


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
            connect_timeout_seconds=settings.polza_connect_timeout_seconds,
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
