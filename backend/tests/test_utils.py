import string

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from backend.main import client_ip, sse_event, validate_text
from backend.models import cache_key, request_id


def test_sse_event_format():
    payload = {"text": "\u04d9\u04af\u04e9"}
    encoded = sse_event("delta", payload)
    assert encoded.startswith("event: delta\ndata: ")
    assert encoded.endswith("\n\n")
    assert '"text":' in encoded


def test_sse_event_injection_safe():
    payload = {"text": "line1\nline2\r\n:bad\ndata: evil"}
    encoded = sse_event("delta", payload)
    lines = encoded.splitlines()
    assert lines[0].startswith("event: delta")
    assert lines[1].startswith("data: ")
    assert lines[2] == ""
    assert len(lines) == 3


def test_validate_text_accepts_valid_input():
    validate_text("ok", 10)


def test_validate_text_rejects_empty():
    with pytest.raises(HTTPException):
        validate_text("   ", 10)


def test_validate_text_rejects_too_long():
    with pytest.raises(HTTPException):
        validate_text("hello", 3)


def test_cache_key_deterministic():
    key1 = cache_key("text")
    key2 = cache_key("text")
    key3 = cache_key("another")
    assert key1 == key2
    assert key1 != key3


def test_request_id_hex():
    rid = request_id()
    assert len(rid) == 32
    assert set(rid) <= set(string.hexdigits.lower())


def test_client_ip_parses_forwarded_for():
    scope = {
        "type": "http",
        "headers": [(b"x-forwarded-for", b"1.2.3.4, 5.6.7.8")],
        "client": ("9.9.9.9", 1234),
    }
    request = Request(scope)
    assert client_ip(request) == "1.2.3.4"
