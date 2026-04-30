"""FastAPI entrypoint for the Tatar GEC backend.

The module initializes shared runtime state, exposes health and metrics
routes, and implements both one-shot and SSE streaming correction APIs
with validation, rate limiting, caching, and error mapping.
"""

import asyncio
import ipaddress
import json
import logging
import time
from collections.abc import AsyncGenerator
from typing import Any

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse

from .cache import SimpleCache
from .gemini import GeminiKeyExhausted
from .metrics import (
    CACHE_HITS,
    METRICS_CONTENT_TYPE,
    REQUEST_LATENCY,
    REQUESTS_TOTAL,
    STREAM_DURATION,
    STREAMS_ACTIVE,
    STREAMS_TOTAL,
    render_metrics,
)
from .models import ModelAdapter, build_adapter, cache_key, request_id
from .polza import PolzaRateLimited
from .rate_limit import SlidingLimiter
from .settings import Settings, get_settings

app = FastAPI(title="Tatar GEC")
load_dotenv()


class AppState:
    """Holds shared runtime state for the API process."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self.adapter: ModelAdapter = build_adapter(settings)
        logger = logging.getLogger("backend")
        logger.info("Model adapter: %s", self.adapter.name)
        if hasattr(self.adapter, "_model"):
            logger.info("Gemini model: %s", self.adapter._model)
        self.cache = SimpleCache(settings.cache_ttl_ms)
        self.rates = SlidingLimiter(settings.rate_limit_per_minute, settings.rate_limit_per_day)
        self.trusted_proxy_ips = set(settings.trusted_proxy_ips)
        self.streams: dict[str, int] = {}
        self.started_at = time.time()
        self.total_requests = 0
        self.total_invalid = 0
        self.total_rate_limited = 0
        self.total_errors = 0
        self.total_cache_hits = 0
        self.total_streams_started = 0
        self.total_streams_done = 0
        self.total_streams_cancelled = 0
        self.total_streams_error = 0


async def get_state() -> AppState:
    """Return (and lazily initialize) the singleton application state."""
    if not hasattr(app.state, "app_state"):
        app.state.app_state = AppState(get_settings())
    return app.state.app_state


@app.get("/health")
async def health():
    """Simple liveness probe for load balancers."""
    return {"status": "ok"}


@app.get("/version")
async def version(state: AppState = Depends(get_state)):
    """Return build metadata for the running service."""
    return {
        "service": state.settings.service_name,
        "version": state.settings.version,
        "git": state.settings.git_sha,
    }


@app.get("/status")
async def status(state: AppState = Depends(get_state)):
    """Expose runtime counters and limits for diagnostics."""
    uptime = int(time.time() - state.started_at)
    return {
        "status": "ok",
        "uptime_seconds": uptime,
        "active_streams": sum(state.streams.values()),
        "requests_total": state.total_requests,
        "invalid_requests_total": state.total_invalid,
        "rate_limited_total": state.total_rate_limited,
        "errors_total": state.total_errors,
        "cache_hits_total": state.total_cache_hits,
        "streams": {
            "started": state.total_streams_started,
            "done": state.total_streams_done,
            "cancelled": state.total_streams_cancelled,
            "error": state.total_streams_error,
        },
        "limits": {
            "max_concurrent_streams": state.settings.max_concurrent_streams,
            "rate_limit_per_minute": state.settings.rate_limit_per_minute,
            "rate_limit_per_day": state.settings.rate_limit_per_day,
        },
    }


@app.get("/metrics")
async def metrics():
    """Expose Prometheus metrics in the expected content type."""
    return Response(render_metrics(), media_type=METRICS_CONTENT_TYPE)


def record_request_outcome(endpoint: str, outcome: str, started_at: float | None = None) -> None:
    """Update request counters and optional latency metric."""
    REQUESTS_TOTAL.labels(endpoint=endpoint, outcome=outcome).inc()
    if started_at is not None:
        REQUEST_LATENCY.labels(endpoint=endpoint).observe(time.time() - started_at)


def record_invalid_request(state: AppState, endpoint: str, started_at: float | None = None) -> None:
    """Track invalid input outcomes for one endpoint."""
    state.total_invalid += 1
    record_request_outcome(endpoint, "invalid_input", started_at)


def record_rate_limited(state: AppState, endpoint: str, started_at: float | None = None) -> None:
    """Track rate-limit outcomes for one endpoint."""
    state.total_rate_limited += 1
    record_request_outcome(endpoint, "rate_limited", started_at)


async def parse_and_validate_correction_request(
    request: Request, max_body_bytes: int, max_chars: int
) -> tuple[str, str]:
    """Parse and validate correction request payload."""
    ensure_json_request(request)
    await enforce_body_size(request, max_body_bytes)
    body = await parse_json_body(request)
    text = str(body.get("text", ""))
    lang = resolve_correction_lang(body)
    validate_text(text, max_chars)
    return text, lang


@app.post("/v1/correct")
async def correct(request: Request, state: AppState = Depends(get_state)):
    """Handle one-shot correction requests."""
    state.total_requests += 1
    started = time.time()
    try:
        text, lang = await parse_and_validate_correction_request(
            request, state.settings.max_body_bytes, state.settings.max_chars
        )
    except HTTPException:
        record_invalid_request(state, "correct", started)
        raise
    ip = client_ip(request, state.trusted_proxy_ips)
    if not state.rates.allow(ip):
        record_rate_limited(state, "correct", started)
        raise HTTPException(status_code=429, detail={"error": "rate_limited"})

    rid = request_id()
    cached = state.cache.get(cache_key(text))
    if cached:
        state.total_cache_hits += 1
        CACHE_HITS.inc()
        record_request_outcome("correct", "cache", started)
        return {
            "request_id": rid,
            "corrected_text": cached.value,
            "meta": {"model_backend": cached.backend, "latency_ms": 0},
        }

    try:
        corrected = await state.adapter.correct(text, lang, rid)
    except GeminiKeyExhausted as err:
        record_rate_limited(state, "correct", started)
        raise HTTPException(
            status_code=429,
            detail={"error": "rate_limited", "message": str(err)},
        ) from err
    except Exception as err:  # noqa: BLE001
        state.total_errors += 1
        record_request_outcome("correct", "error", started)
        raise HTTPException(
            status_code=500, detail={"error": "server_error", "request_id": rid}
        ) from err

    state.cache.set(cache_key(text), corrected, state.adapter.name)
    latency = int((time.time() - started) * 1000)
    record_request_outcome("correct", "ok", started)
    return {
        "request_id": rid,
        "corrected_text": corrected,
        "meta": {"model_backend": state.adapter.name, "latency_ms": latency},
    }


@app.post("/v1/correct/stream")
async def correct_stream(request: Request, state: AppState = Depends(get_state)):
    """Stream correction output as server-sent events."""
    state.total_requests += 1
    try:
        text, lang = await parse_and_validate_correction_request(
            request, state.settings.max_body_bytes, state.settings.max_chars
        )
    except HTTPException:
        record_invalid_request(state, "stream")
        raise
    ip = client_ip(request, state.trusted_proxy_ips)
    if not state.rates.allow(ip):
        record_rate_limited(state, "stream")
        raise HTTPException(status_code=429, detail={"error": "rate_limited"})

    # concurrency guard
    count = state.streams.get(ip, 0)
    if count >= state.settings.max_concurrent_streams:
        record_rate_limited(state, "stream")
        raise HTTPException(
            status_code=429, detail={"error": "rate_limited", "message": "too_many_streams"}
        )
    state.streams[ip] = count + 1

    rid = request_id()
    started = time.time()
    state.total_streams_started += 1
    STREAMS_ACTIVE.inc()
    outcome_recorded = False

    def record_stream_outcome(outcome: str):
        """Emit stream completion metrics once per request."""
        nonlocal outcome_recorded
        if outcome_recorded:
            return
        outcome_recorded = True
        REQUESTS_TOTAL.labels(endpoint="stream", outcome=outcome).inc()
        STREAMS_TOTAL.labels(outcome=outcome).inc()
        STREAM_DURATION.observe(time.time() - started)

    stream_iter = state.adapter.correct_stream(text, lang, rid)
    first_delta: str | None = None
    stream_finished = False
    if getattr(state.adapter, "prefetch_first_chunk", False):
        try:
            first_delta = await stream_iter.__anext__()
        except StopAsyncIteration:
            stream_finished = True
        except GeminiKeyExhausted as err:
            record_rate_limited(state, "stream")
            record_stream_outcome("rate_limited")
            state.streams[ip] = max(0, state.streams.get(ip, 1) - 1)
            STREAMS_ACTIVE.dec()
            raise HTTPException(
                status_code=429,
                detail={"error": "rate_limited", "message": str(err)},
            ) from err
        except PolzaRateLimited:
            record_rate_limited(state, "stream")
            record_stream_outcome("rate_limited")
            state.streams[ip] = max(0, state.streams.get(ip, 1) - 1)
            STREAMS_ACTIVE.dec()
            raise HTTPException(status_code=429, detail={"error": "rate_limited"}) from None

    async def event_stream() -> AsyncGenerator[str, None]:
        """Yield SSE frames while keeping metrics and cache in sync."""
        interval = state.settings.heartbeat_ms / 1000
        corrected = ""
        pending_delta = first_delta
        try:
            yield sse_event("meta", {"request_id": rid, "model_backend": state.adapter.name})
            if stream_finished:
                latency = int((time.time() - started) * 1000)
                yield sse_event("done", {"request_id": rid, "latency_ms": latency})
                state.total_streams_done += 1
                record_stream_outcome("ok")
                return
            while True:
                try:
                    if pending_delta is not None:
                        delta = pending_delta
                        pending_delta = None
                    else:
                        delta = await asyncio.wait_for(stream_iter.__anext__(), timeout=interval)
                    corrected += delta
                    yield sse_event("delta", {"request_id": rid, "text": delta})
                except TimeoutError:
                    yield ": ping\n\n"
                except StopAsyncIteration:
                    latency = int((time.time() - started) * 1000)
                    yield sse_event("done", {"request_id": rid, "latency_ms": latency})
                    if corrected:
                        state.cache.set(cache_key(text), corrected, state.adapter.name)
                    state.total_streams_done += 1
                    record_stream_outcome("ok")
                    break
        except GeminiKeyExhausted as err:
            yield sse_event(
                "error",
                {"request_id": rid, "type": "rate_limited", "message": str(err)},
            )
            state.total_rate_limited += 1
            record_stream_outcome("rate_limited")
            state.total_streams_error += 1
        except PolzaRateLimited:
            yield sse_event(
                "error",
                {"request_id": rid, "type": "rate_limited", "message": "rate_limited"},
            )
            state.total_rate_limited += 1
            record_stream_outcome("rate_limited")
            state.total_streams_error += 1
        except asyncio.CancelledError:
            yield sse_event(
                "error", {"request_id": rid, "type": "cancelled", "message": "client_disconnected"}
            )
            state.total_streams_cancelled += 1
            record_stream_outcome("cancelled")
        except Exception as err:  # noqa: BLE001
            yield sse_event(
                "error", {"request_id": rid, "type": "server_error", "message": str(err)}
            )
            state.total_streams_error += 1
            state.total_errors += 1
            record_stream_outcome("error")
        finally:
            state.streams[ip] = max(0, state.streams.get(ip, 1) - 1)
            STREAMS_ACTIVE.dec()

    headers = {
        "Cache-Control": "no-cache",
        "X-Accel-Buffering": "no",
        "Connection": "keep-alive",
    }
    return StreamingResponse(event_stream(), media_type="text/event-stream", headers=headers)


def sse_event(event: str, data: dict[str, Any]) -> str:
    """Format an SSE event payload."""
    import json

    return f"event: {event}\ndata: {json.dumps(data, ensure_ascii=False)}\n\n"


def validate_text(text: str, max_chars: int):
    """Reject empty or oversized text inputs."""
    if not text or not text.strip():
        raise HTTPException(status_code=400, detail={"error": "invalid_input", "message": "empty"})
    if len(text) > max_chars:
        raise HTTPException(
            status_code=400, detail={"error": "invalid_input", "message": "too_long"}
        )


def resolve_correction_lang(payload: dict[str, Any]) -> str:
    """Accept only Tatar correction language and default missing values to tt."""
    raw = payload.get("lang")
    if raw is None:
        return "tt"
    if not isinstance(raw, str):
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_input", "message": "invalid_lang"},
        )
    value = raw.strip().lower()
    if not value:
        return "tt"
    if value != "tt":
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_input", "message": "unsupported_lang"},
        )
    return "tt"


def ensure_json_request(request: Request) -> None:
    """Ensure the request uses application/json."""
    content_type = request.headers.get("content-type", "")
    media_type = content_type.split(";", 1)[0].strip().lower()
    if media_type != "application/json":
        raise HTTPException(status_code=415, detail={"error": "unsupported_media_type"})


async def enforce_body_size(request: Request, max_bytes: int) -> None:
    """Reject requests with bodies that exceed the configured limit."""
    length = request.headers.get("content-length")
    if length:
        try:
            if int(length) > max_bytes:
                raise HTTPException(status_code=413, detail={"error": "payload_too_large"})
        except ValueError:
            pass
    body = await request.body()
    if len(body) > max_bytes:
        raise HTTPException(status_code=413, detail={"error": "payload_too_large"})


async def parse_json_body(request: Request) -> dict[str, Any]:
    """Parse a JSON object payload with helpful error messages."""
    try:
        payload = await request.json()
    except json.JSONDecodeError as err:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_input", "message": "invalid_json"},
        ) from err
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_input", "message": "invalid_body"},
        )
    return payload


def client_ip(request: Request, trusted_proxy_ips: set[str] | None = None) -> str:
    """Resolve client IP and trust forwarded headers only from known proxies."""
    direct_ip = request.client.host if request.client else "unknown"
    if not trusted_proxy_ips or direct_ip not in trusted_proxy_ips:
        return direct_ip

    forwarded = request.headers.get("x-forwarded-for", "")
    if not forwarded:
        return direct_ip

    candidate = forwarded.split(",", 1)[0].strip()
    if not candidate:
        return direct_ip
    try:
        ipaddress.ip_address(candidate)
    except ValueError:
        return direct_ip
    return candidate


# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
