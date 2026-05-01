import asyncio
import json
import random
import string
from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient

from backend.main import AppState, app
from backend.models import ModelAdapter
from backend.settings import Settings


class DeterministicAdapter(ModelAdapter):
    name = "test"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        return " ".join(text.split()).strip().capitalize()

    async def correct_stream(
        self, text: str, lang: str, request_id: str
    ) -> AsyncGenerator[str, None]:  # noqa: ARG002
        corrected = await self.correct(text, lang, request_id)
        for chunk in [corrected[i : i + 5] for i in range(0, len(corrected), 5)]:
            yield chunk


def setup_state(**overrides):
    if "model_backend" not in overrides:
        overrides["model_backend"] = "polza"
    if "polza_api_key" not in overrides:
        overrides["polza_api_key"] = "test-polza-key"
    if "polza_model" not in overrides:
        overrides["polza_model"] = "google/gemini-3.1-flash-lite-preview"
    if "trusted_proxy_ips" not in overrides:
        overrides["trusted_proxy_ips"] = ["127.0.0.1", "::1", "testclient"]
    settings = Settings(**overrides)
    app.state.app_state = AppState(settings)
    app.state.app_state.adapter = DeterministicAdapter()
    return app


def make_client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


async def get_status(client: AsyncClient):
    response = await client.get("/status")
    assert response.status_code == 200
    return response.json()


@pytest.mark.asyncio
async def test_health():
    setup_state()
    async with make_client() as client:
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_status_and_metrics():
    setup_state()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            json={"text": "hello"},
        )
        assert response.status_code == 200

        status = await client.get("/status")
        assert status.status_code == 200
        payload = status.json()
        assert payload["requests_total"] >= 1
        assert "active_streams" in payload

        metrics = await client.get("/metrics")
        assert metrics.status_code == 200
        assert "gec_requests_total" in metrics.text


@pytest.mark.asyncio
async def test_basic_headers():
    setup_state()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            json={"text": "hello"},
            headers={"origin": "http://example.com"},
        )
        assert response.status_code == 200
        assert response.headers.get("content-type", "").startswith("application/json")
        assert response.headers.get("access-control-allow-origin") == "*"


@pytest.mark.asyncio
async def test_content_type_enforced():
    setup_state()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            content=json.dumps({"text": "hello"}),
            headers={"Content-Type": "text/plain"},
        )
        assert response.status_code == 415
        assert response.json()["detail"]["error"] == "unsupported_media_type"

        stream_response = await client.post(
            "/v1/correct/stream",
            content=json.dumps({"text": "hello"}),
            headers={"Content-Type": "text/plain"},
        )
        assert stream_response.status_code == 415
        assert stream_response.json()["detail"]["error"] == "unsupported_media_type"


@pytest.mark.asyncio
async def test_payload_too_large():
    setup_state(max_body_bytes=60, max_chars=1000, rate_limit_per_minute=1000)
    payload = json.dumps({"text": "a" * 200})
    headers = {"Content-Type": "application/json"}
    async with make_client() as client:
        response = await client.post("/v1/correct", content=payload, headers=headers)
        assert response.status_code == 413
        assert response.json()["detail"]["error"] == "payload_too_large"

        stream_response = await client.post(
            "/v1/correct/stream",
            content=payload,
            headers=headers,
        )
        assert stream_response.status_code == 413
        assert stream_response.json()["detail"]["error"] == "payload_too_large"


@pytest.mark.asyncio
async def test_metrics_increment_once():
    setup_state(rate_limit_per_minute=1000, rate_limit_per_day=1000)
    async with make_client() as client:
        before = await client.get("/metrics")
        before_value = metric_value(
            before.text,
            "gec_requests_total",
            [("endpoint", "correct"), ("outcome", "ok")],
        )

        response = await client.post("/v1/correct", json={"text": "hello"})
        assert response.status_code == 200

        after = await client.get("/metrics")
        after_value = metric_value(
            after.text,
            "gec_requests_total",
            [("endpoint", "correct"), ("outcome", "ok")],
        )
        assert after_value == before_value + 1


@pytest.mark.asyncio
async def test_version():
    setup_state(service_name="svc", version="1.2.3", git_sha="abc")
    async with make_client() as client:
        response = await client.get("/version")
        assert response.status_code == 200
        payload = response.json()
        assert payload["service"] == "svc"
        assert payload["version"] == "1.2.3"
        assert payload["git"] == "abc"


@pytest.mark.asyncio
async def test_openapi_schema():
    setup_state()
    async with make_client() as client:
        response = await client.get("/openapi.json")
        assert response.status_code == 200
        payload = response.json()
        assert payload.get("openapi")


@pytest.mark.asyncio
async def test_validation_errors():
    setup_state(max_chars=4)
    async with make_client() as client:
        empty = await client.post("/v1/correct", json={"text": " ", "lang": "tt"})
        assert empty.status_code == 400

        too_long = await client.post("/v1/correct", json={"text": "hello", "lang": "tt"})
        assert too_long.status_code == 400

        empty_stream = await client.post(
            "/v1/correct/stream",
            json={"text": " ", "lang": "tt"},
        )
        assert empty_stream.status_code == 400

        too_long_stream = await client.post(
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        )
        assert too_long_stream.status_code == 400

        status = await get_status(client)
        assert status["invalid_requests_total"] >= 2


@pytest.mark.asyncio
async def test_error_schema_contracts():
    setup_state(max_chars=4, rate_limit_per_minute=1, rate_limit_per_day=10)
    async with make_client() as client:
        invalid = await client.post("/v1/correct", json={"text": " "})
        assert invalid.status_code == 400
        payload = invalid.json()
        assert payload["detail"]["error"] == "invalid_input"
        assert payload["detail"]["message"] == "empty"

        too_long = await client.post("/v1/correct", json={"text": "hello"})
        assert too_long.status_code == 400
        payload = too_long.json()
        assert payload["detail"]["error"] == "invalid_input"
        assert payload["detail"]["message"] == "too_long"

        ok = await client.post(
            "/v1/correct",
            json={"text": "hey"},
            headers={"x-forwarded-for": "1.2.3.4"},
        )
        assert ok.status_code == 200

        limited = await client.post(
            "/v1/correct",
            json={"text": "hey"},
            headers={"x-forwarded-for": "1.2.3.4"},
        )
        assert limited.status_code == 429
        payload = limited.json()
        assert payload["detail"]["error"] == "rate_limited"


@pytest.mark.asyncio
async def test_validation_boundaries():
    setup_state(max_chars=5, rate_limit_per_minute=1000, rate_limit_per_day=1000)
    async with make_client() as client:
        ok = await client.post("/v1/correct", json={"text": "abcde"})
        assert ok.status_code == 200

        too_long = await client.post("/v1/correct", json={"text": "abcdef"})
        assert too_long.status_code == 400

        whitespace = await client.post("/v1/correct", json={"text": "\n\t "})
        assert whitespace.status_code == 400


@pytest.mark.asyncio
async def test_max_chars_enforced_stream_and_non_stream():
    setup_state(max_chars=3, rate_limit_per_minute=1000, rate_limit_per_day=1000)
    async with make_client() as client:
        ok = await client.post("/v1/correct", json={"text": "hey"})
        assert ok.status_code == 200

        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hey"},
        ) as response:
            assert response.status_code == 200
            await collect_events(response)

        too_long = await client.post("/v1/correct", json={"text": "heyy"})
        assert too_long.status_code == 400

        too_long_stream = await client.post(
            "/v1/correct/stream",
            json={"text": "heyy"},
        )
        assert too_long_stream.status_code == 400


@pytest.mark.asyncio
async def test_validation_fuzz():
    max_chars = 40
    setup_state(max_chars=max_chars, rate_limit_per_minute=10000, rate_limit_per_day=10000)
    rng = random.Random(0)
    tatar_letters = "\u04d9\u04d8\u04af\u04ae\u04e9\u04e8\u04a3\u04a2\u0497\u0496\u04bb\u04ba"
    alphabet = string.ascii_letters + string.digits + " \t\n" + tatar_letters
    texts = [
        "",
        " ",
        "\n\t",
        "a" * max_chars,
        "a" * (max_chars + 1),
    ]
    for _ in range(120):
        length = rng.randint(0, max_chars + 20)
        texts.append("".join(rng.choice(alphabet) for _ in range(length)))

    async with make_client() as client:
        for text in texts:
            response = await client.post(
                "/v1/correct",
                json={"text": text, "lang": "tt"},
            )
            valid = bool(text.strip()) and len(text) <= max_chars
            if valid:
                assert response.status_code == 200
                assert "corrected_text" in response.json()
            else:
                assert response.status_code == 400
                payload = response.json()
                assert payload["detail"]["error"] == "invalid_input"


@pytest.mark.asyncio
async def test_rate_limit():
    setup_state(rate_limit_per_minute=1, rate_limit_per_day=10)
    headers = {"x-forwarded-for": "1.2.3.4"}
    async with make_client() as client:
        first = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
            headers=headers,
        )
        assert first.status_code == 200

        second = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
            headers=headers,
        )
        assert second.status_code == 429

        status = await get_status(client)
        assert status["rate_limited_total"] >= 1


@pytest.mark.asyncio
async def test_rate_limit_forwarded_chain():
    setup_state(rate_limit_per_minute=1, rate_limit_per_day=10)
    async with make_client() as client:
        first = await client.post(
            "/v1/correct",
            json={"text": "hello"},
            headers={"x-forwarded-for": "1.1.1.1, 2.2.2.2"},
        )
        assert first.status_code == 200

        blocked = await client.post(
            "/v1/correct",
            json={"text": "hello"},
            headers={"x-forwarded-for": "1.1.1.1, 2.2.2.2"},
        )
        assert blocked.status_code == 429

        other = await client.post(
            "/v1/correct",
            json={"text": "hello"},
            headers={"x-forwarded-for": "2.2.2.2, 1.1.1.1"},
        )
        assert other.status_code == 200


@pytest.mark.asyncio
async def test_rate_limit_per_ip_isolation():
    setup_state(rate_limit_per_minute=1, rate_limit_per_day=10)
    async with make_client() as client:
        first = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
            headers={"x-forwarded-for": "1.2.3.4"},
        )
        assert first.status_code == 200

        blocked = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
            headers={"x-forwarded-for": "1.2.3.4"},
        )
        assert blocked.status_code == 429

        other = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
            headers={"x-forwarded-for": "5.6.7.8"},
        )
        assert other.status_code == 200


@pytest.mark.asyncio
async def test_rate_limit_burst_behavior():
    setup_state(rate_limit_per_minute=2, rate_limit_per_day=10)
    headers = {"x-forwarded-for": "9.9.9.9"}
    async with make_client() as client:
        first = await client.post("/v1/correct", json={"text": "hello"}, headers=headers)
        second = await client.post("/v1/correct", json={"text": "hello"}, headers=headers)
        third = await client.post("/v1/correct", json={"text": "hello"}, headers=headers)

        assert first.status_code == 200
        assert second.status_code == 200
        assert third.status_code == 429


@pytest.mark.asyncio
async def test_rate_limit_abuse():
    setup_state(rate_limit_per_minute=1, rate_limit_per_day=10)
    headers = {"x-forwarded-for": "7.7.7.7"}
    async with make_client() as client:
        first = await client.post("/v1/correct", json={"text": "hello"}, headers=headers)
        assert first.status_code == 200

        blocked = []
        for _ in range(4):
            response = await client.post("/v1/correct", json={"text": "hello"}, headers=headers)
            blocked.append(response.status_code)

        assert all(code == 429 for code in blocked)

        status = await get_status(client)
        assert status["rate_limited_total"] >= 4


@pytest.mark.asyncio
async def test_concurrency_guard_is_per_ip():
    setup_state(max_concurrent_streams=1, rate_limit_per_minute=1000, rate_limit_per_day=1000)
    app.state.app_state.streams["1.1.1.1"] = 1
    async with (
        make_client() as client,
        client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello"},
            headers={"x-forwarded-for": "2.2.2.2"},
        ) as response,
    ):
        assert response.status_code == 200
        await collect_events(response)


@pytest.mark.asyncio
async def test_lang_field_is_ignored_and_tatar_is_always_used():
    setup_state()
    async with make_client() as client:
        response = await client.post("/v1/correct", json={"text": "hello"})
        assert response.status_code == 200

        ignored = await client.post("/v1/correct", json={"text": "hello", "lang": "ru"})
        assert ignored.status_code == 200

        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello"},
        ) as stream_response:
            assert stream_response.status_code == 200
            await collect_events(stream_response)

        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "en"},
        ) as stream_response:
            assert stream_response.status_code == 200


@pytest.mark.asyncio
async def test_cache_hit():
    setup_state()
    async with make_client() as client:
        first = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert first.status_code == 200

        second = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert second.status_code == 200
        assert second.json()["meta"]["latency_ms"] == 0

        metrics = await client.get("/metrics")
        assert "gec_cache_hits_total" in metrics.text


async def collect_events(response):
    events = []
    current_event = "message"
    current_data = ""
    async for line in response.aiter_lines():
        if line == "":
            if current_data:
                payload = json.loads(current_data)
                events.append((current_event, payload))
            current_event = "message"
            current_data = ""
            continue
        if line.startswith("event:"):
            current_event = line.replace("event:", "").strip()
        elif line.startswith("data:"):
            data_part = line.replace("data:", "").strip()
            if current_data:
                current_data += "\n"
            current_data += data_part
    return events


def metric_value(metrics_text: str, name: str, labels: list[tuple[str, str]]) -> float:
    label_str = ",".join([f'{key}="{value}"' for key, value in labels])
    prefix = f"{name}{{{label_str}}}"
    for line in metrics_text.splitlines():
        if line.startswith(prefix):
            return float(line.split()[-1])
    return 0.0


@pytest.mark.asyncio
async def test_streaming_events():
    setup_state()
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            assert "text/event-stream" in response.headers.get("content-type", "")
            assert "no-cache" in response.headers.get("cache-control", "")
            assert response.headers.get("x-accel-buffering") == "no"
            events = await collect_events(response)

        event_names = [name for name, _ in events]
        assert event_names[0] == "meta"
        assert "delta" in event_names
        assert event_names[-1] == "done"

        request_id = next(payload["request_id"] for name, payload in events if name == "meta")
        for _, payload in events:
            assert payload["request_id"] == request_id


@pytest.mark.asyncio
async def test_sse_schema_contract():
    setup_state(heartbeat_ms=200)
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            events = await collect_events(response)

        meta = next(payload for name, payload in events if name == "meta")
        assert meta.get("request_id")
        assert meta.get("model_backend")

        delta = next(payload for name, payload in events if name == "delta")
        assert "text" in delta

        done = next(payload for name, payload in events if name == "done")
        assert "latency_ms" in done

    setup_state()
    app.state.app_state.adapter = FailingAdapter()
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            events = await collect_events(response)

        error_payload = next(payload for name, payload in events if name == "error")
        assert error_payload.get("request_id")
        assert error_payload.get("type")
        assert error_payload.get("message")


@pytest.mark.asyncio
async def test_stream_event_ordering_contract():
    setup_state(heartbeat_ms=200)
    app.state.app_state.adapter = SlowAdapter(0.01, ["a", "b"])
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            events = await collect_events(response)

        event_names = [name for name, _ in events]
        assert event_names[0] == "meta"
        assert event_names[-1] == "done"
        assert "delta" in event_names


@pytest.mark.asyncio
async def test_metrics_after_stream():
    setup_state()
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            await collect_events(response)

        metrics = await client.get("/metrics")
        assert metrics.status_code == 200
        assert 'gec_streams_total{outcome="ok"}' in metrics.text


@pytest.mark.asyncio
async def test_stream_result_cached():
    setup_state()
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            await collect_events(response)

        cached = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert cached.status_code == 200
        assert cached.json()["meta"]["latency_ms"] == 0


class FailingAdapter(ModelAdapter):
    name = "fail"

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        raise RuntimeError("boom")

    async def correct_stream(
        self,
        text: str,
        lang: str,
        request_id: str,
    ) -> AsyncGenerator[str, None]:
        raise RuntimeError("boom")
        yield ""  # pragma: no cover


class SlowAdapter(ModelAdapter):
    name = "slow"

    def __init__(self, delay: float, chunks: list[str] | None = None):
        self.delay = delay
        self.chunks = chunks or ["hello"]

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        return "".join(self.chunks)

    async def correct_stream(
        self,
        text: str,
        lang: str,
        request_id: str,
    ) -> AsyncGenerator[str, None]:
        for chunk in self.chunks:
            await asyncio.sleep(self.delay)
            yield chunk


@pytest.mark.asyncio
async def test_stream_error_event():
    setup_state()
    app.state.app_state.adapter = FailingAdapter()
    async with make_client() as client:
        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response:
            assert response.status_code == 200
            events = await collect_events(response)

        event_names = [name for name, _ in events]
        assert "error" in event_names

        error_payload = next(payload for name, payload in events if name == "error")
        assert error_payload["type"] == "server_error"
        assert "request_id" in error_payload

        status = await get_status(client)
        assert status["errors_total"] >= 1
        assert status["streams"]["error"] >= 1

        metrics = await client.get("/metrics")
        assert 'gec_streams_total{outcome="error"}' in metrics.text


@pytest.mark.asyncio
async def test_correct_error_increments_counters():
    setup_state()
    app.state.app_state.adapter = FailingAdapter()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert response.status_code == 500
        payload = response.json()
        assert payload["detail"]["error"] == "server_error"
        assert payload["detail"]["request_id"]

        status = await get_status(client)
        assert status["errors_total"] >= 1
        assert status["requests_total"] >= 1


@pytest.mark.asyncio
async def test_error_mapping_consistency():
    setup_state()
    app.state.app_state.adapter = FailingAdapter()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert response.status_code == 500
        payload = response.json()
        assert payload["detail"]["error"] == "server_error"
        assert payload["detail"]["request_id"]

        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as stream_response:
            assert stream_response.status_code == 200
            events = await collect_events(stream_response)

        error_payload = next(payload for name, payload in events if name == "error")
        assert error_payload["type"] == "server_error"
        assert error_payload["request_id"]

        metrics = await client.get("/metrics")
        assert metrics.status_code == 200
        assert 'gec_requests_total{endpoint="correct",outcome="error"}' in metrics.text
        assert 'gec_requests_total{endpoint="stream",outcome="error"}' in metrics.text


@pytest.mark.asyncio
async def test_response_metadata_no_internal_leak():
    setup_state()
    async with make_client() as client:
        response = await client.post(
            "/v1/correct",
            json={"text": "hello", "lang": "tt"},
        )
        assert response.status_code == 200
        meta = response.json()["meta"]
        assert "model_backend" in meta
        assert "cache_ttl_ms" not in meta
        assert "rate_limit_per_minute" not in meta

        async with client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as stream_response:
            assert stream_response.status_code == 200
            events = await collect_events(stream_response)

        meta_event = next(payload for name, payload in events if name == "meta")
        assert "request_id" in meta_event


@pytest.mark.asyncio
async def test_active_streams_status():
    setup_state()
    app.state.app_state.streams = {"1.1.1.1": 2, "2.2.2.2": 1}
    async with make_client() as client:
        status = await get_status(client)
        assert status["active_streams"] == 3


@pytest.mark.asyncio
async def test_stream_heartbeat_comment():
    setup_state(heartbeat_ms=5)
    app.state.app_state.adapter = SlowAdapter(0.02, ["hello"])
    async with (
        make_client() as client,
        client.stream(
            "POST",
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
        ) as response,
    ):
        assert response.status_code == 200
        saw_ping = False
        lines = response.aiter_lines()
        for _ in range(10):
            line = await asyncio.wait_for(lines.__anext__(), timeout=0.2)
            if line.startswith(": ping"):
                saw_ping = True
                break
            if line.startswith("event: delta"):
                break

        assert saw_ping is True


@pytest.mark.asyncio
async def test_stream_concurrency_limit():
    setup_state(max_concurrent_streams=1, rate_limit_per_minute=100, rate_limit_per_day=100)
    headers = {"x-forwarded-for": "5.6.7.8"}
    app.state.app_state.streams["5.6.7.8"] = 1
    async with make_client() as client:
        blocked = await client.post(
            "/v1/correct/stream",
            json={"text": "hello", "lang": "tt"},
            headers=headers,
        )
        assert blocked.status_code == 429
