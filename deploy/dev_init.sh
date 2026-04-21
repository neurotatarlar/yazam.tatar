#!/usr/bin/env bash
set -euo pipefail

APP_USER=${APP_USER:-gec-tt-bot}
APP_DIR=${APP_DIR:-/opt/gec_tt}
WEB_DIR=${WEB_DIR:-/var/www/gec_tt}
NGINX_SITE=${NGINX_SITE:-/etc/nginx/sites-available/gec-annotation.conf}
NGINX_SNIPPET=/etc/nginx/snippets/gec-tt-app.conf
NGINX_BROTLI_SNIPPET=/etc/nginx/snippets/gec-tt-brotli.conf
NGINX_SITE_TEMPLATE=${NGINX_SITE_TEMPLATE:-$INIT_ROOT/deploy/nginx/gec-tt-site.conf}
NGINX_SERVER_NAME=${NGINX_SERVER_NAME:-_}
SERVICE_NAME=gec-tt-backend
SERVICE_PATH=/etc/systemd/system/${SERVICE_NAME}.service
VPN_POLICY_SERVICE=gec-tt-vpn-policy
VPN_POLICY_SERVICE_PATH=/etc/systemd/system/${VPN_POLICY_SERVICE}.service
VPN_POLICY_SCRIPT_PATH=/usr/local/bin/gec-tt-vpn-policy
INIT_ROOT=${INIT_ROOT:-/tmp/gec-tt-init}
ENV_SRC=${ENV_SRC:-$INIT_ROOT/.env.example}
SERVICE_SRC=${SERVICE_SRC:-$INIT_ROOT/deploy/systemd/gec-tt-backend.service}
VPN_POLICY_SERVICE_SRC=${VPN_POLICY_SERVICE_SRC:-$INIT_ROOT/deploy/systemd/gec-tt-vpn-policy.service}
VPN_POLICY_SCRIPT_SRC=${VPN_POLICY_SCRIPT_SRC:-$INIT_ROOT/deploy/gec-tt-vpn-policy.sh}
NGINX_SRC=${NGINX_SRC:-$INIT_ROOT/deploy/nginx/gec-tt-app.conf}
NGINX_BROTLI_SRC=${NGINX_BROTLI_SRC:-$INIT_ROOT/deploy/nginx/gec-tt-brotli.conf}
WG_INTERFACE=${WG_INTERFACE:-wg0}
WG_CONF_PATH=/etc/wireguard/${WG_INTERFACE}.conf
PYTHON_BIN=${PYTHON_BIN:-}

if [ ! -f "$ENV_SRC" ] || [ ! -f "$SERVICE_SRC" ] || [ ! -f "$NGINX_SRC" ]; then
  echo "Missing init assets in $INIT_ROOT" >&2
  exit 1
fi

if [ -z "$PYTHON_BIN" ]; then
  if command -v python3.11 >/dev/null 2>&1; then
    PYTHON_BIN=python3.11
  else
    PYTHON_BIN=python3
  fi
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "Python binary not found: $PYTHON_BIN" >&2
  exit 1
fi

"$PYTHON_BIN" - <<'PY'
import sys

if sys.version_info < (3, 11):
    raise SystemExit("Python >=3.11 is required for backend deployment")
PY

if ! id -u "$APP_USER" >/dev/null 2>&1; then
  sudo useradd --create-home --shell /bin/bash "$APP_USER"
fi

sudo mkdir -p "$APP_DIR" "$WEB_DIR"
sudo chown -R "$APP_USER":"$APP_USER" "$APP_DIR" "$WEB_DIR"

RECREATE_VENV=false
if [ -x "$APP_DIR/venv/bin/python" ]; then
  if ! sudo -u "$APP_USER" "$APP_DIR/venv/bin/python" - <<'PY'
import sys

raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
  then
    RECREATE_VENV=true
  fi
fi

if [ "$RECREATE_VENV" = true ]; then
  sudo rm -rf "$APP_DIR/venv"
fi

if [ ! -d "$APP_DIR/venv" ]; then
  sudo -u "$APP_USER" "$PYTHON_BIN" -m venv "$APP_DIR/venv"
fi

sudo -u "$APP_USER" "$APP_DIR/venv/bin/pip" install --upgrade pip setuptools wheel

if [ ! -f "$APP_DIR/.env" ]; then
  sudo install -m 600 -o "$APP_USER" -g "$APP_USER" "$ENV_SRC" "$APP_DIR/.env"
fi

tmp_service="$(mktemp)"
sed -e "s|__APP_USER__|$APP_USER|g" -e "s|__APP_DIR__|$APP_DIR|g" "$SERVICE_SRC" > "$tmp_service"
sudo install -m 644 "$tmp_service" "$SERVICE_PATH"
rm -f "$tmp_service"

if [ -f "$VPN_POLICY_SCRIPT_SRC" ]; then
  sudo install -m 755 "$VPN_POLICY_SCRIPT_SRC" "$VPN_POLICY_SCRIPT_PATH"
fi
if [ -f "$VPN_POLICY_SERVICE_SRC" ]; then
  sudo install -m 644 "$VPN_POLICY_SERVICE_SRC" "$VPN_POLICY_SERVICE_PATH"
fi

if [ -n "${WG_CONFIG:-}" ]; then
  sudo install -d -m 700 /etc/wireguard
  if [ -f "$WG_CONF_PATH" ]; then
    sudo cp -a "$WG_CONF_PATH" "${WG_CONF_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
  fi
  printf '%s\n' "$WG_CONFIG" | sudo tee "$WG_CONF_PATH" >/dev/null
  if ! sudo grep -qE '^Table[[:space:]]*=' "$WG_CONF_PATH"; then
    sudo sed -i '/^\[Interface\]/a Table = off' "$WG_CONF_PATH"
  else
    sudo sed -i 's/^Table[[:space:]]*=.*/Table = off/' "$WG_CONF_PATH"
  fi
  sudo chmod 600 "$WG_CONF_PATH"
fi

sudo install -m 644 "$NGINX_SRC" "$NGINX_SNIPPET"
if nginx -V 2>&1 | grep -qi brotli; then
  sudo install -m 644 "$NGINX_BROTLI_SRC" "$NGINX_BROTLI_SNIPPET"
else
  sudo install -m 644 /dev/null "$NGINX_BROTLI_SNIPPET"
fi
if [ ! -f "$NGINX_SITE" ]; then
  if [ ! -f "$NGINX_SITE_TEMPLATE" ]; then
    echo "Nginx site not found and no template provided: $NGINX_SITE" >&2
    exit 1
  fi
  tmp_site="$(mktemp)"
  sed "s|__SERVER_NAME__|$NGINX_SERVER_NAME|g" "$NGINX_SITE_TEMPLATE" > "$tmp_site"
  sudo install -m 644 "$tmp_site" "$NGINX_SITE"
  rm -f "$tmp_site"
fi

if [[ "$NGINX_SITE" == /etc/nginx/sites-available/* ]]; then
  site_name="$(basename "$NGINX_SITE")"
  sudo ln -sfn "$NGINX_SITE" "/etc/nginx/sites-enabled/$site_name"
  if [ "$site_name" != "default" ]; then
    sudo rm -f /etc/nginx/sites-enabled/default
  fi
fi

if ! sudo grep -qF "$NGINX_SNIPPET" "$NGINX_SITE"; then
  sudo python3 - <<PY
from pathlib import Path

path = Path("$NGINX_SITE")
text = path.read_text()
snippet = "    include $NGINX_SNIPPET;"
idx = text.rfind("}")
if idx == -1:
    raise SystemExit("Nginx site has no closing brace")
text = f"{text[:idx]}\n{snippet}\n{text[idx:]}"
path.write_text(text)
PY
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

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"
if [ -f "$VPN_POLICY_SERVICE_PATH" ]; then
  sudo systemctl enable "$VPN_POLICY_SERVICE"
fi
if [ -n "${WG_CONFIG:-}" ]; then
  sudo systemctl enable --now "wg-quick@${WG_INTERFACE}"
  if [ -f "$VPN_POLICY_SERVICE_PATH" ]; then
    sudo systemctl restart "$VPN_POLICY_SERVICE"
  fi
fi

sudo nginx -t
sudo systemctl reload nginx
