import pytest

from backend.models import FallbackAdapter, ModelAdapter, backend_name, build_adapter, normalize
from backend.polza import PolzaRetryableError
from backend.settings import Settings


def test_normalize():
    assert normalize("  hello   world ") == "Hello world"


def test_build_adapter_polza_without_gemini_fallback():
    adapter = build_adapter(
        Settings(
            model_backend="polza",
            polza_api_key="polza-key",
            polza_model="google/gemini-3.1-flash-lite-preview",
            gemini_api_keys=[],
        )
    )
    assert adapter.name == "polza"


def test_build_adapter_polza_with_gemini_fallback():
    adapter = build_adapter(
        Settings(
            model_backend="polza",
            polza_api_key="polza-key",
            polza_model="google/gemini-3.1-flash-lite-preview",
            gemini_api_keys=["gemini-key"],
        )
    )
    assert isinstance(adapter, FallbackAdapter)


def test_build_adapter_rejects_unsupported_backend():
    try:
        build_adapter(Settings(model_backend="mock"))
    except ValueError as err:
        assert "Unsupported MODEL_BACKEND" in str(err)
    else:
        raise AssertionError("Unsupported backend should raise ValueError")


class _PrimaryOk(ModelAdapter):
    name = "polza"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        return "primary"

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        yield "pri"
        yield "mary"


class _PrimaryRetryable(ModelAdapter):
    name = "polza"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        raise PolzaRetryableError("temporary", status_code=503)

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        raise PolzaRetryableError("temporary", status_code=503)
        yield ""


class _FallbackOk(ModelAdapter):
    name = "gemini"

    async def correct(self, text: str, lang: str, request_id: str) -> str:  # noqa: ARG002
        return "fallback"

    async def correct_stream(self, text: str, lang: str, request_id: str):  # noqa: ARG002
        yield "fall"
        yield "back"


@pytest.mark.asyncio
async def test_backend_name_reports_primary_when_fallback_wrapper_primary_succeeds():
    adapter = FallbackAdapter(_PrimaryOk(), _FallbackOk())

    assert await adapter.correct("text", "tt", "rid") == "primary"
    assert backend_name(adapter) == "polza"


@pytest.mark.asyncio
async def test_backend_name_reports_fallback_when_retryable_primary_fails():
    adapter = FallbackAdapter(_PrimaryRetryable(), _FallbackOk())

    assert await adapter.correct("text", "tt", "rid") == "fallback"
    assert backend_name(adapter) == "gemini"


@pytest.mark.asyncio
async def test_backend_name_reports_stream_primary_after_first_chunk():
    adapter = FallbackAdapter(_PrimaryOk(), _FallbackOk())
    stream = adapter.correct_stream("text", "tt", "rid")

    assert await stream.__anext__() == "pri"
    assert backend_name(adapter) == "polza"


@pytest.mark.asyncio
async def test_backend_name_reports_stream_fallback_after_retryable_primary_failure():
    adapter = FallbackAdapter(_PrimaryRetryable(), _FallbackOk())
    stream = adapter.correct_stream("text", "tt", "rid")

    assert await stream.__anext__() == "fall"
    assert backend_name(adapter) == "gemini"
