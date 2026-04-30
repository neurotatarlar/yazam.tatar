#!/usr/bin/env python3
"""Validate static web assets and translation consistency."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
I18N_DIR = ROOT / "client" / "assets" / "i18n"
WEBAPP_DIR = ROOT / "webapp"


def load_json(path: Path) -> dict[str, str]:
    return json.loads(path.read_text(encoding="utf-8"))


def ensure_files_exist() -> None:
    required = [
        WEBAPP_DIR / "index.html",
        WEBAPP_DIR / "styles.css",
        WEBAPP_DIR / "app.js",
        ROOT / "deploy" / "build_web_static.sh",
        ROOT / "client" / "assets" / "config.json",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if missing:
        raise SystemExit(f"Missing required web files: {', '.join(missing)}")


def ensure_i18n_keys_match() -> None:
    en = load_json(I18N_DIR / "en.json")
    ru = load_json(I18N_DIR / "ru.json")
    tt = load_json(I18N_DIR / "tt.json")

    reference = set(en.keys())
    for name, payload in [("ru.json", ru), ("tt.json", tt)]:
        keys = set(payload.keys())
        missing = sorted(reference - keys)
        extra = sorted(keys - reference)
        if missing or extra:
            details = []
            if missing:
                details.append(f"missing: {', '.join(missing)}")
            if extra:
                details.append(f"extra: {', '.join(extra)}")
            raise SystemExit(f"i18n key mismatch in {name}: {'; '.join(details)}")


def ensure_i18n_keys_used() -> None:
    en = load_json(I18N_DIR / "en.json")
    index = (WEBAPP_DIR / "index.html").read_text(encoding="utf-8")
    app_js = (WEBAPP_DIR / "app.js").read_text(encoding="utf-8")

    used_in_html = set(re.findall(r'data-i18n(?:-title)?="([^"]+)"', index))
    used_in_js = set(re.findall(r"\bt\(\s*'([^']+)'", app_js))
    used = used_in_html | used_in_js
    unused = sorted(set(en.keys()) - used)
    if unused:
        raise SystemExit(f"Unused i18n keys in en.json: {', '.join(unused)}")


if __name__ == "__main__":
    ensure_files_exist()
    ensure_i18n_keys_match()
    ensure_i18n_keys_used()
    print("web static checks passed")
