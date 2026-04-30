import os
import shutil
import subprocess

import httpx
import pytest

from backend.tests.helpers import free_port, start_server, stop_server, wait_ready


@pytest.mark.e2e
@pytest.mark.asyncio
@pytest.mark.skipif(os.getenv("RUN_E2E") != "1", reason="e2e tests disabled")
async def test_minimal_e2e_stream():
    port = free_port()
    process = start_server(
        port,
        {
            "MAX_CONCURRENT_STREAMS": "2",
            "RATE_LIMIT_PER_MINUTE": "1000",
            "RATE_LIMIT_PER_DAY": "1000",
            "MODEL_BACKEND": "mock",
        },
    )
    base_url = f"http://127.0.0.1:{port}"
    try:
        await wait_ready(base_url)
        async with (
            httpx.AsyncClient(base_url=base_url, timeout=10.0) as client,
            client.stream(
                "POST",
                "/v1/correct/stream",
                json={"text": "hello", "lang": "tt"},
            ) as response,
        ):
            assert response.status_code == 200
            events = []
            current_event = "message"
            current_data = ""
            async for line in response.aiter_lines():
                if line == "":
                    if current_data:
                        events.append(current_event)
                    current_event = "message"
                    current_data = ""
                    continue
                if line.startswith("event:"):
                    current_event = line.replace("event:", "").strip()
                elif line.startswith("data:"):
                    current_data = line.replace("data:", "").strip()
            assert "meta" in events
            assert "delta" in events
            assert "done" in events
    finally:
        stop_server(process)


@pytest.mark.e2e
@pytest.mark.asyncio
@pytest.mark.skipif(os.getenv("RUN_E2E") != "1", reason="e2e tests disabled")
async def test_cli_smoke():
    if shutil.which("curl") is None:
        pytest.skip("curl not available")
    port = free_port()
    process = start_server(
        port,
        {
            "MAX_CONCURRENT_STREAMS": "2",
            "RATE_LIMIT_PER_MINUTE": "1000",
            "RATE_LIMIT_PER_DAY": "1000",
            "MODEL_BACKEND": "mock",
        },
    )
    try:
        await wait_ready(f"http://127.0.0.1:{port}")
        command = [
            "curl",
            "-N",
            "--max-time",
            "5",
            "-X",
            "POST",
            f"http://127.0.0.1:{port}/v1/correct/stream",
            "-H",
            "Content-Type: application/json",
            "-d",
            '{"text":"hello","lang":"tt"}',
        ]
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        output = result.stdout
        assert "event: meta" in output
        assert "event: delta" in output
        assert "event: done" in output
    finally:
        stop_server(process)
