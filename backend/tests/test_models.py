import pytest

from backend.models import FallbackAdapter, MockAdapter, build_adapter, normalize
from backend.settings import Settings


@pytest.mark.asyncio
async def test_mock_adapter_stream_roundtrip():
    adapter = MockAdapter()
    text = "hello   world"
    corrected = await adapter.correct(text, "tt", "rid")

    chunks = []
    async for chunk in adapter.correct_stream(text, "tt", "rid"):
        chunks.append(chunk)

    assert "".join(chunks) == corrected


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
