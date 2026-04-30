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
