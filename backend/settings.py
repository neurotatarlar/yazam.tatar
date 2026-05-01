"""Environment-driven configuration for backend runtime defaults."""

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


def _get_bool(name: str, default: bool) -> bool:
    """Fetch a boolean environment variable with a default."""
    raw = os.getenv(name)
    if raw is None:
        return default
    value = raw.strip().lower()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    return default


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
    trusted_proxy_ips: list[str] = field(
        default_factory=lambda: _get_list("TRUSTED_PROXY_IPS") or ["127.0.0.1", "::1"]
    )
    model_backend: str = field(default_factory=lambda: _get("MODEL_BACKEND", "polza"))
    cache_ttl_ms: int = field(default_factory=lambda: _get_int("CACHE_TTL_MS", 60000))
    gemini_model: str = field(
        default_factory=lambda: _get("GEMINI_MODEL", "gemini-3-flash-preview")
    )
    gemini_api_keys: list[str] = field(default_factory=lambda: _get_list("GEMINI_API_KEYS"))
    polza_base_url: str = field(
        default_factory=lambda: _get("POLZA_BASE_URL", "https://polza.ai/api/v1")
    )
    polza_api_key: str = field(default_factory=lambda: _get("POLZA_API_KEY", ""))
    polza_model: str = field(
        default_factory=lambda: _get("POLZA_MODEL", "google/gemini-3.1-flash-lite-preview")
    )
    polza_timeout_seconds: int = field(
        default_factory=lambda: _get_int("POLZA_TIMEOUT_SECONDS", 25)
    )
    polza_provider_allow_fallbacks: bool = field(
        default_factory=lambda: _get_bool("POLZA_PROVIDER_ALLOW_FALLBACKS", False)
    )
    polza_provider_only: list[str] = field(
        default_factory=lambda: _get_list("POLZA_PROVIDER_ONLY") or ["Google"]
    )


def get_settings() -> Settings:
    """Construct settings with current environment values."""
    return Settings()
