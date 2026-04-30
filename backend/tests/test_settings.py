from backend.settings import Settings


def test_settings_invalid_int_falls_back(monkeypatch):
    monkeypatch.setenv("RATE_LIMIT_PER_MINUTE", "nope")
    monkeypatch.setenv("MAX_CONCURRENT_STREAMS", "NaN")
    settings = Settings()

    assert settings.rate_limit_per_minute == 60
    assert settings.max_concurrent_streams == 3
    assert settings.trusted_proxy_ips == ["127.0.0.1", "::1"]


def test_settings_parses_trusted_proxy_ips(monkeypatch):
    monkeypatch.setenv("TRUSTED_PROXY_IPS", "10.0.0.1, 10.0.0.2")
    settings = Settings()

    assert settings.trusted_proxy_ips == ["10.0.0.1", "10.0.0.2"]


def test_polza_defaults(monkeypatch):
    monkeypatch.delenv("POLZA_PROVIDER_ONLY", raising=False)
    monkeypatch.delenv("POLZA_PROVIDER_ALLOW_FALLBACKS", raising=False)
    settings = Settings()

    assert settings.polza_base_url == "https://polza.ai/api/v1"
    assert settings.polza_model == "google/gemini-3.1-flash-lite-preview"
    assert settings.polza_provider_allow_fallbacks is False
    assert settings.polza_provider_only == ["Google"]


def test_polza_boolean_and_list_parsing(monkeypatch):
    monkeypatch.setenv("POLZA_PROVIDER_ALLOW_FALLBACKS", "true")
    monkeypatch.setenv("POLZA_PROVIDER_ONLY", "Google,OpenRouter")
    settings = Settings()

    assert settings.polza_provider_allow_fallbacks is True
    assert settings.polza_provider_only == ["Google", "OpenRouter"]
