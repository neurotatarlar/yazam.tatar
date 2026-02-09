"""Tiny in-memory cache with time-based eviction."""

import time


class CacheEntry:
    """Represents a cached correction value."""

    def __init__(self, value, backend: str, expires_at: float):
        self.value = value
        self.backend = backend
        self.expires_at = expires_at


class SimpleCache:
    """In-memory TTL cache keyed by request payload."""

    def __init__(self, ttl_ms: int):
        self.store: dict[str, CacheEntry] = {}
        self.ttl_ms = ttl_ms

    def get(self, key: str) -> CacheEntry | None:
        """Return a cached entry if present and not expired."""
        entry = self.store.get(key)
        if not entry:
            return None
        if time.time() * 1000 > entry.expires_at:
            self.store.pop(key, None)
            return None
        return entry

    def set(self, key: str, value, backend: str):
        """Insert or overwrite a cache entry."""
        self.store[key] = CacheEntry(value, backend, time.time() * 1000 + self.ttl_ms)
