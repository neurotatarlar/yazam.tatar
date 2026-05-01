from backend.models import FallbackAdapter, build_adapter, normalize
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
