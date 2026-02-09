"""In-memory sliding-window limiter for minute/day quotas."""

import time


class SlidingLimiter:
    """Track request timestamps per key for minute/day limits."""

    def __init__(self, per_minute: int, per_day: int):
        self.per_minute = per_minute
        self.per_day = per_day
        self.minute: dict[str, list[float]] = {}
        self.day: dict[str, list[float]] = {}

    def allow(self, key: str) -> bool:
        """Return True if the key is within both rate limits."""
        now = time.time()
        minute_window = now - 60
        day_window = now - 86400
        self.minute.setdefault(key, [])
        self.day.setdefault(key, [])
        self.minute[key] = [t for t in self.minute[key] if t >= minute_window]
        self.day[key] = [t for t in self.day[key] if t >= day_window]
        if len(self.minute[key]) >= self.per_minute or len(self.day[key]) >= self.per_day:
            return False
        self.minute[key].append(now)
        self.day[key].append(now)
        return True
