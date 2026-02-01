"""Environment-backed configuration for the backend."""

import os
from dataclasses import dataclass, field


def _get(name: str, default: str) -> str:
    """Fetch a string environment variable with a default."""
    return os.getenv(name, default)


def _get_int(name: str, default: int) -> int:
    """Fetch an integer environment variable with a default."""
    try:
        return int(os.getenv(name, default))
    except (TypeError, ValueError):
        return default


def _get_list(name: str) -> list[str]:
    """Fetch a comma-delimited list from the environment."""
    raw = os.getenv(name, "")
    return [item.strip() for item in raw.split(",") if item.strip()]


@dataclass
class Settings:
    """Typed configuration loaded from environment variables."""

    port: int = field(default_factory=lambda: _get_int("PORT", 3000))
    service_name: str = field(default_factory=lambda: _get("SERVICE_NAME", "tatar-gec"))
    version: str = field(default_factory=lambda: _get("VERSION", "0.1.0"))
    git_sha: str = field(default_factory=lambda: _get("GIT_SHA", "dev"))
    max_chars: int = field(default_factory=lambda: _get_int("MAX_CHARS", 5000))
    max_body_bytes: int = field(default_factory=lambda: _get_int("MAX_BODY_BYTES", 200000))
    rate_limit_per_minute: int = field(
        default_factory=lambda: _get_int("RATE_LIMIT_PER_MINUTE", 60)
    )
    rate_limit_per_day: int = field(default_factory=lambda: _get_int("RATE_LIMIT_PER_DAY", 1000))
    max_concurrent_streams: int = field(
        default_factory=lambda: _get_int("MAX_CONCURRENT_STREAMS", 3)
    )
    heartbeat_ms: int = field(default_factory=lambda: _get_int("HEARTBEAT_MS", 20000))
    model_backend: str = field(default_factory=lambda: _get("MODEL_BACKEND", "gemini"))
    prompt_version: str = field(default_factory=lambda: _get("PROMPT_VERSION", "v1"))
    cache_ttl_ms: int = field(default_factory=lambda: _get_int("CACHE_TTL_MS", 60000))
    gemini_model: str = field(
        default_factory=lambda: _get("GEMINI_MODEL", "gemini-3-flash-preview")
    )
    gemini_api_keys: list[str] = field(default_factory=lambda: _get_list("GEMINI_API_KEYS"))


def get_settings() -> Settings:
    """Construct settings with current environment values."""
    return Settings()
