#!/usr/bin/env bash
set -euo pipefail

OUT_DIR=${1:-build/web}
WEB_BASE_HREF=${WEB_BASE_HREF:-/}
API_BASE_URL=${API_BASE_URL:-/api}
BUILD_SHA=${BUILD_SHA:-dev}

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cp -a webapp/. "$OUT_DIR/"
mkdir -p "$OUT_DIR/assets"
cp -a client/assets/. "$OUT_DIR/assets/"

cp -a client/web/icons "$OUT_DIR/"
cp client/web/favicon.png "$OUT_DIR/"
cp client/web/manifest.json "$OUT_DIR/"
cp client/web/robots.txt "$OUT_DIR/"
cp client/web/sitemap.xml "$OUT_DIR/"

export OUT_DIR WEB_BASE_HREF API_BASE_URL BUILD_SHA

python3 - <<'PY'
import json
import os
from pathlib import Path

out = Path(os.environ['OUT_DIR'])
base_href = os.environ['WEB_BASE_HREF']
if not base_href.startswith('/') or not base_href.endswith('/'):
    raise SystemExit(f'WEB_BASE_HREF must start and end with "/": {base_href}')

index_path = out / 'index.html'
index_text = index_path.read_text(encoding='utf-8')
index_text = index_text.replace('__BASE_HREF__', base_href)
index_path.write_text(index_text, encoding='utf-8')

config_path = out / 'assets' / 'config.json'
config = json.loads(config_path.read_text(encoding='utf-8'))
config['baseUrl'] = os.environ['API_BASE_URL']
config['buildSha'] = os.environ['BUILD_SHA']
config_path.write_text(json.dumps(config, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PY
