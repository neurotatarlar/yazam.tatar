#!/usr/bin/env bash
set -euo pipefail

PRIMARY_DOMAIN=${PRIMARY_DOMAIN:-}
EXTRA_DOMAINS=${EXTRA_DOMAINS:-}
CERTBOT_EMAIL=${CERTBOT_EMAIL:-}
NGINX_SITE=${NGINX_SITE:-/etc/nginx/sites-available/gec-tt.conf}
TLS_SNIPPET=${TLS_SNIPPET:-/etc/nginx/snippets/gec-tt-tls-hardening.conf}
CHECK_RENEW_DRY_RUN=${CHECK_RENEW_DRY_RUN:-false}

if [ -z "$PRIMARY_DOMAIN" ]; then
  echo "PRIMARY_DOMAIN is required" >&2
  exit 1
fi
if [ -z "$CERTBOT_EMAIL" ]; then
  echo "CERTBOT_EMAIL is required" >&2
  exit 1
fi
if [ ! -f "$NGINX_SITE" ]; then
  echo "Nginx site not found: $NGINX_SITE" >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx

domain_args=(-d "$PRIMARY_DOMAIN")
while IFS= read -r domain; do
  if [ -n "$domain" ]; then
    domain_args+=(-d "$domain")
  fi
done < <(printf '%s' "$EXTRA_DOMAINS" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d')

sudo certbot \
  --nginx \
  --non-interactive \
  --agree-tos \
  --no-eff-email \
  --email "$CERTBOT_EMAIL" \
  --redirect \
  --keep-until-expiring \
  "${domain_args[@]}"

tmp_tls="$(mktemp)"
cat > "$tmp_tls" <<'EOF'
# TLS hardening without OCSP stapling (Let's Encrypt no longer provides OCSP URLs).
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
EOF
sudo install -m 644 "$tmp_tls" "$TLS_SNIPPET"
rm -f "$tmp_tls"

sudo NGINX_SITE="$NGINX_SITE" TLS_SNIPPET="$TLS_SNIPPET" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["NGINX_SITE"])
snippet = f'    include {os.environ["TLS_SNIPPET"]};'
text = path.read_text()

if snippet in text:
    raise SystemExit(0)

server_start = text.find("server {")
if server_start < 0:
    raise SystemExit("Nginx site has no server block")

depth = 0
block_end = -1
for i in range(server_start, len(text)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            block_end = i
            break

if block_end < 0:
    raise SystemExit("Nginx site server block is malformed")

insert = "\n" + snippet + "\n"
updated = text[:block_end] + insert + text[block_end:]
path.write_text(updated)
PY

if [ "$CHECK_RENEW_DRY_RUN" = "true" ]; then
  sudo certbot renew --dry-run
fi

sudo nginx -t
sudo systemctl reload nginx
