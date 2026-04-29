#!/usr/bin/env bash
set -euo pipefail

WEB_DIR="${1:-build/web-dev}"
PORT="${PORT:-3000}"
PYTHON_BIN="${PYTHON:-python3}"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  local pids=()
  if [[ -n "${HTTP_PID:-}" ]]; then
    pids+=("${HTTP_PID}")
  fi
  if [[ -n "${UVICORN_PID:-}" ]]; then
    pids+=("${UVICORN_PID}")
  fi

  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
    fi
  done

  # Uvicorn --reload spawns child workers; terminate those explicitly.
  if [[ -n "${UVICORN_PID:-}" ]]; then
    pkill -TERM -P "${UVICORN_PID}" 2>/dev/null || true
  fi

  sleep 0.25

  for pid in "${pids[@]}"; do
    if kill -0 "${pid}" 2>/dev/null; then
      kill -KILL "${pid}" 2>/dev/null || true
    fi
  done

  if [[ -n "${UVICORN_PID:-}" ]]; then
    pkill -KILL -P "${UVICORN_PID}" 2>/dev/null || true
  fi

  if [[ "${#pids[@]}" -gt 0 ]]; then
    wait "${pids[@]}" 2>/dev/null || true
  fi

  return "${exit_code}"
}

trap cleanup EXIT INT TERM

WEB_BASE_HREF="${WEB_BASE_HREF:-/}" \
API_BASE_URL="${API_BASE_URL:-http://127.0.0.1:${PORT}}" \
BUILD_SHA="${BUILD_SHA:-dev}" \
./deploy/build_web_static.sh "${WEB_DIR}"

"${PYTHON_BIN}" -m uvicorn backend.main:app --reload --port "${PORT}" &
UVICORN_PID=$!

"${PYTHON_BIN}" -m http.server --directory "${WEB_DIR}" 8080 &
HTTP_PID=$!

wait "${UVICORN_PID}" "${HTTP_PID}"
