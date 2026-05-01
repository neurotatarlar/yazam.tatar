"""Polza.ai adapter with OpenAI-compatible chat completion calls."""

from __future__ import annotations

import json
import logging
from collections.abc import AsyncGenerator
from dataclasses import dataclass

import httpx

from .correction_policy import build_system_instruction, sanitize_user_text
from .models import ModelAdapter


class PolzaError(RuntimeError):
    """Base class for upstream Polza errors."""

    def __init__(self, message: str, *, status_code: int | None = None, code: str | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code


class PolzaRetryableError(PolzaError):
    """Transient Polza error that can trigger fallback."""


class PolzaRateLimited(PolzaRetryableError):
    """Polza rate limit or provider quota exhaustion."""


class PolzaNonRetryableError(PolzaError):
    """Permanent Polza error that should not trigger fallback."""


@dataclass(slots=True)
class PolzaProviderConfig:
    """Provider routing configuration sent to Polza."""

    allow_fallbacks: bool
    only: list[str]

    def as_payload(self) -> dict[str, object]:
        payload: dict[str, object] = {"allow_fallbacks": self.allow_fallbacks}
        if self.only:
            payload["only"] = self.only
        return payload


class PolzaAdapter(ModelAdapter):
    """Model adapter that calls Polza Chat Completions API."""

    name = "polza"
    prefetch_first_chunk = True

    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str,
        timeout_seconds: int,
        provider: PolzaProviderConfig,
    ):
        self._api_key = api_key.strip()
        self._model = model.strip()
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds
        self._provider = provider
        self._logger = logging.getLogger("backend")

        if not self._api_key:
            raise PolzaNonRetryableError("Polza API key is not configured.")
        if not self._model:
            raise PolzaNonRetryableError("Polza model is not configured.")

    async def correct(self, text: str, lang: str, request_id: str) -> str:
        """Return full corrected text from a non-streaming Polza call."""
        payload = self._build_payload(text, lang, request_id, stream=False)
        response = await self._post_json(payload)
        usage_obj = response.get("usage")
        usage = usage_obj if isinstance(usage_obj, dict) else None
        self._log_usage(usage, request_id=request_id)
        return extract_content(response)

    async def correct_stream(
        self, text: str, lang: str, request_id: str
    ) -> AsyncGenerator[str, None]:
        """Yield correction deltas from Polza streaming response."""
        payload = self._build_payload(text, lang, request_id, stream=True)
        url = f"{self._base_url}/chat/completions"
        headers = self._headers()

        timeout = httpx.Timeout(connect=5.0, read=None, write=10.0, pool=5.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                async with client.stream("POST", url, headers=headers, json=payload) as response:
                    if response.status_code >= 400:
                        error_body = await response.aread()
                        self._raise_for_status(
                            response.status_code, error_body.decode("utf-8", errors="replace")
                        )
                    emitted_any = False
                    async for line in response.aiter_lines():
                        if not line:
                            continue
                        if line.startswith(":"):
                            continue
                        if not line.startswith("data:"):
                            continue
                        data = line[5:].strip()
                        if data == "[DONE]":
                            return
                        chunk = parse_sse_chunk(data)
                        if chunk is None:
                            continue
                        error_obj = chunk.get("error")
                        if isinstance(error_obj, dict):
                            message_obj = error_obj.get("message")
                            message = (
                                str(message_obj)
                                if isinstance(message_obj, str)
                                else "Upstream request failed."
                            )
                            code_obj = error_obj.get("code")
                            code = str(code_obj) if isinstance(code_obj, str) else None
                            self._raise_from_error(message=message, code=code, status_code=200)

                        usage = chunk.get("usage")
                        if isinstance(usage, dict):
                            self._log_usage(usage, request_id=request_id)

                        choices = chunk.get("choices")
                        if not isinstance(choices, list) or not choices:
                            continue
                        first = choices[0]
                        if not isinstance(first, dict):
                            continue
                        delta = first.get("delta")
                        if not isinstance(delta, dict):
                            delta = {}

                        delta_text = extract_text_value(delta.get("content"))
                        if delta_text:
                            emitted_any = True
                            yield delta_text
                            continue

                        # Some providers return full message text in chunk.message.content.
                        if not emitted_any:
                            message_payload = first.get("message")
                            if isinstance(message_payload, dict):
                                message_text = extract_text_value(message_payload.get("content"))
                                if message_text:
                                    emitted_any = True
                                    yield message_text
            except httpx.TimeoutException as err:
                raise PolzaRetryableError("Polza request timed out.") from err
            except httpx.RequestError as err:
                raise PolzaRetryableError("Polza request failed.") from err

    def _build_payload(
        self, text: str, lang: str, request_id: str, *, stream: bool
    ) -> dict[str, object]:
        sanitized_text = sanitize_user_text(text)
        return {
            "model": self._model,
            "messages": [
                {"role": "system", "content": build_system_instruction(lang, request_id)},
                {"role": "user", "content": sanitized_text},
            ],
            "temperature": 0,
            "stream": stream,
            "provider": self._provider.as_payload(),
        }

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }

    async def _post_json(self, payload: dict[str, object]) -> dict[str, object]:
        url = f"{self._base_url}/chat/completions"
        timeout = httpx.Timeout(connect=5.0, read=float(self._timeout), write=10.0, pool=5.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                response = await client.post(url, headers=self._headers(), json=payload)
            except httpx.TimeoutException as err:
                raise PolzaRetryableError("Polza request timed out.") from err
            except httpx.RequestError as err:
                raise PolzaRetryableError("Polza request failed.") from err
        self._raise_for_status(response.status_code, response.text)
        data = response.json()
        if not isinstance(data, dict):
            raise PolzaRetryableError("Unexpected Polza response format.")
        error_obj = data.get("error")
        if isinstance(error_obj, dict):
            message_obj = error_obj.get("message")
            message = (
                str(message_obj) if isinstance(message_obj, str) else "Upstream request failed."
            )
            code_obj = error_obj.get("code")
            code = str(code_obj) if isinstance(code_obj, str) else None
            self._raise_from_error(message=message, code=code, status_code=response.status_code)
        return data

    def _raise_for_status(self, status_code: int, body_text: str) -> None:
        if status_code < 400:
            return
        message, code = parse_error_message(body_text)
        self._raise_from_error(message=message, code=code, status_code=status_code)

    def _raise_from_error(self, *, message: str, code: str | None, status_code: int) -> None:
        if status_code == 429:
            raise PolzaRateLimited(message, status_code=status_code, code=code)
        # If Polza balance is exhausted, fallback to direct Gemini (free tier) when configured.
        if status_code in {402, 408, 500, 502, 503}:
            raise PolzaRetryableError(message, status_code=status_code, code=code)
        if code == "INSUFFICIENT_BALANCE":
            raise PolzaRetryableError(message, status_code=status_code, code=code)
        raise PolzaNonRetryableError(message, status_code=status_code, code=code)

    def _log_usage(self, usage: dict[str, object] | None, *, request_id: str) -> None:
        if usage is None:
            return
        total_tokens = usage.get("total_tokens")
        cost_rub = usage.get("cost_rub")
        if total_tokens is None and cost_rub is None:
            return
        self._logger.info(
            "polza_usage request_id=%s model=%s total_tokens=%s cost_rub=%s",
            request_id,
            self._model,
            total_tokens,
            cost_rub,
        )


def parse_sse_chunk(raw: str) -> dict[str, object] | None:
    """Parse one SSE data line payload."""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def parse_error_message(body_text: str) -> tuple[str, str | None]:
    """Extract a concise message/code from Polza error JSON."""
    fallback_message = "Upstream request failed."
    try:
        data = json.loads(body_text)
    except json.JSONDecodeError:
        return fallback_message, None
    if not isinstance(data, dict):
        return fallback_message, None
    error = data.get("error")
    if isinstance(error, dict):
        message = error.get("message")
        code = error.get("code")
        return (
            message if isinstance(message, str) and message else fallback_message,
            code if isinstance(code, str) else None,
        )
    return fallback_message, None


def extract_content(payload: dict[str, object]) -> str:
    """Extract assistant message content from chat completion response."""
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise PolzaRetryableError("Polza response has no choices.")
    first = choices[0] if isinstance(choices[0], dict) else {}
    message = first.get("message")
    if not isinstance(message, dict):
        raise PolzaRetryableError("Polza response has no message content.")
    content = message.get("content")
    text = extract_text_value(content)
    if text:
        return text
    raise PolzaRetryableError("Polza response content is missing.")


def extract_text_value(content: object) -> str:
    """Extract plain text from string or OpenAI-style content-part arrays."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        text_parts: list[str] = []
        for item in content:
            if not isinstance(item, dict):
                continue
            if item.get("type") != "text":
                continue
            text = item.get("text")
            if isinstance(text, str):
                text_parts.append(text)
        return "".join(text_parts)
    return ""
