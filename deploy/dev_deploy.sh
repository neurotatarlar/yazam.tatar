#!/usr/bin/env bash
set -euo pipefail

APP_USER=${APP_USER:-gec-tt-bot}
APP_DIR=${APP_DIR:-/opt/gec_tt}
WEB_DIR=${WEB_DIR:-/var/www/gec_tt}
WHEEL_PATH=${WHEEL_PATH:-/tmp/gec-tt-backend.whl}
WEB_ARCHIVE=${WEB_ARCHIVE:-/tmp/gec-tt-web.tar.gz}
SERVICE_NAME=${SERVICE_NAME:-gec-tt-backend}
APP_VERSION=${APP_VERSION:-}
APP_GIT_SHA=${APP_GIT_SHA:-}
MODEL_BACKEND=${MODEL_BACKEND:-polza}
NGINX_SNIPPET_SRC=${NGINX_SNIPPET_SRC:-/tmp/gec-tt-app.conf}
NGINX_BROTLI_SRC=${NGINX_BROTLI_SRC:-/tmp/gec-tt-brotli.conf}
NGINX_SNIPPET_DST=${NGINX_SNIPPET_DST:-/etc/nginx/snippets/gec-tt-app.conf}
NGINX_BROTLI_DST=${NGINX_BROTLI_DST:-/etc/nginx/snippets/gec-tt-brotli.conf}

HAS_WHEEL=false
HAS_WEB=false
if [ -n "$WHEEL_PATH" ] && [ -f "$WHEEL_PATH" ]; then
  HAS_WHEEL=true
fi
if [ -n "$WEB_ARCHIVE" ] && [ -f "$WEB_ARCHIVE" ]; then
  HAS_WEB=true
fi
if [ "$HAS_WHEEL" = false ] && [ "$HAS_WEB" = false ]; then
  echo "Missing deploy assets." >&2
  exit 1
fi

update_env() {
  local key="$1"
  local value="$2"
  local file="$APP_DIR/.env"
  if [ -z "$value" ]; then
    return
  fi
  if sudo grep -q "^${key}=" "$file"; then
    sudo sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" | sudo tee -a "$file" >/dev/null
  fi
}

if [ "$HAS_WHEEL" = true ]; then
  update_env VERSION "$APP_VERSION"
  update_env GIT_SHA "$APP_GIT_SHA"
  update_env MODEL_BACKEND "${MODEL_BACKEND:-}"
  update_env GEMINI_MODEL "${GEMINI_MODEL:-}"
  update_env GEMINI_API_KEYS "${GEMINI_API_KEYS:-}"
  update_env POLZA_BASE_URL "${POLZA_BASE_URL:-}"
  update_env POLZA_API_KEY "${POLZA_API_KEY:-}"
  update_env POLZA_MODEL "${POLZA_MODEL:-}"
  update_env POLZA_TIMEOUT_SECONDS "${POLZA_TIMEOUT_SECONDS:-}"
  update_env POLZA_PROVIDER_ALLOW_FALLBACKS "${POLZA_PROVIDER_ALLOW_FALLBACKS:-}"
  update_env POLZA_PROVIDER_ONLY "${POLZA_PROVIDER_ONLY:-}"
fi

if [ "$HAS_WHEEL" = true ]; then
  sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --upgrade --force-reinstall "$WHEEL_PATH"
fi

if [ "$HAS_WEB" = true ]; then
  sudo rm -rf "$WEB_DIR"/*
  sudo tar -xzf "$WEB_ARCHIVE" -C "$WEB_DIR"
  sudo chown -R "$APP_USER":"$APP_USER" "$WEB_DIR"
fi
if [ -f "$NGINX_SNIPPET_SRC" ]; then
  sudo install -m 644 "$NGINX_SNIPPET_SRC" "$NGINX_SNIPPET_DST"
fi
if nginx -V 2>&1 | grep -qi brotli; then
  if [ -f "$NGINX_BROTLI_SRC" ]; then
    sudo install -m 644 "$NGINX_BROTLI_SRC" "$NGINX_BROTLI_DST"
  fi
else
  sudo install -m 644 /dev/null "$NGINX_BROTLI_DST"
fi
sudo python3 - <<'PY'
from pathlib import Path

path = Path("/etc/nginx/mime.types")
text = path.read_text()
needs_mjs = "application/javascript mjs;" not in text
needs_wasm = "application/wasm wasm;" not in text
if needs_mjs or needs_wasm:
    lines = text.splitlines()
    out = []
    inserted = False
    for line in lines:
        out.append(line)
        if not inserted and line.strip().startswith("types"):
            if needs_mjs:
                out.append("    application/javascript mjs;")
            if needs_wasm:
                out.append("    application/wasm wasm;")
            inserted = True
    path.write_text("\n".join(out) + "\n")
PY

if [ "$HAS_WHEEL" = true ]; then
  sudo systemctl restart "$SERVICE_NAME"
fi
if [ "$HAS_WEB" = true ]; then
  sudo systemctl reload nginx
fi
