import pytest

from backend.models import FallbackAdapter, ModelAdapter
from backend.polza import (
    PolzaNonRetryableError,
    PolzaRateLimited,
    PolzaRetryableError,
    build_system_instruction,
    extract_content,
    parse_error_message,
    parse_sse_chunk,
)


class _PrimaryRetryable(ModelAdapter):
    name = "polza"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        raise PolzaRetryableError("temporary", status_code=503)

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        raise PolzaRateLimited("rate", status_code=429)
        yield ""


class _PrimaryNonRetryable(ModelAdapter):
    name = "polza"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        raise PolzaNonRetryableError("auth", status_code=401)

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        raise PolzaNonRetryableError("auth", status_code=401)
        yield ""


class _FallbackAdapter(ModelAdapter):
    name = "gemini"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        return "ok"

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        yield "o"
        yield "k"


@pytest.mark.asyncio
async def test_fallback_adapter_for_retryable_error():
    adapter = FallbackAdapter(_PrimaryRetryable(), _FallbackAdapter())
    result = await adapter.correct("text", "tt", "rid")
    assert result == "ok"


@pytest.mark.asyncio
async def test_fallback_adapter_does_not_catch_non_retryable():
    adapter = FallbackAdapter(_PrimaryNonRetryable(), _FallbackAdapter())
    with pytest.raises(PolzaNonRetryableError):
        await adapter.correct("text", "tt", "rid")


@pytest.mark.asyncio
async def test_fallback_adapter_stream_for_retryable_error():
    adapter = FallbackAdapter(_PrimaryRetryable(), _FallbackAdapter())
    chunks = []
    async for chunk in adapter.correct_stream("text", "tt", "rid"):
        chunks.append(chunk)
    assert "".join(chunks) == "ok"


def test_parse_sse_chunk_and_error_message():
    assert parse_sse_chunk('{"choices":[{"delta":{"content":"x"}}]}')
    assert parse_sse_chunk("invalid-json") is None

    msg, code = parse_error_message('{"error":{"message":"oops","code":"RATE"}}')
    assert msg == "oops"
    assert code == "RATE"


def test_extract_content_variants():
    payload: dict[str, object] = {"choices": [{"message": {"content": "value"}}]}
    assert extract_content(payload) == "value"

    list_payload: dict[str, object] = {
        "choices": [
            {
                "message": {
                    "content": [
                        {"type": "text", "text": "va"},
                        {"type": "text", "text": "lue"},
                    ]
                }
            }
        ]
    }
    assert extract_content(list_payload) == "value"


def test_build_system_instruction_contains_lang_and_request_id():
    prompt = build_system_instruction("tt", "rid-1")
    assert "Language: tt" in prompt
    assert "Request-ID: rid-1" in prompt
