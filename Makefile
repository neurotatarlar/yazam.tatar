FLUTTER ?= $(HOME)/flutter/bin/flutter
DART ?= $(HOME)/flutter/bin/dart
PYTHON ?= python3
WEB_WASM ?= false


install:
	$(PYTHON) -m pip install -r requirements.txt

install-dev:
	$(PYTHON) -m pip install -r requirements-dev.txt

client-deps:
	cd client && $(FLUTTER) pub get

dev: client-deps
	@bash -c 'set -euo pipefail; \
	trap "kill 0" EXIT INT TERM; \
	WASM_FLAG=""; \
	if [ "$(WEB_WASM)" = "true" ]; then WASM_FLAG="--wasm"; fi; \
	$(PYTHON) -m uvicorn backend.main:app --reload --port $${PORT:-3000} & \
	cd client && $(FLUTTER) run -d web-server --web-hostname 127.0.0.1 --web-port 8080 $$WASM_FLAG'

test-backend:
	$(PYTHON) -m pytest

test-client: client-deps
	cd client && $(FLUTTER) test

test: test-backend test-client

lint-backend:
	$(PYTHON) -m ruff check backend
	$(PYTHON) -m ruff format --check backend
	$(PYTHON) -m mypy backend

lint-client: client-deps
	cd client && $(DART) format --output=none --set-exit-if-changed lib test
	cd client && $(FLUTTER) analyze --no-version-check

lint: lint-backend lint-client

lint-fix:
	$(PYTHON) -m ruff check backend --fix
	$(PYTHON) -m ruff format backend
	cd client && $(DART) fix --apply
	cd client && $(DART) format lib test

format-backend:
	$(PYTHON) -m ruff format backend

format-client:
	cd client && dart format lib test

format: format-backend format-client

security-backend:
	$(PYTHON) -m bandit -c pyproject.toml -r backend -q
	# TODO: remove ignore once Gemini SDK supports protobuf>=6 (CVE-2026-0994)
	$(PYTHON) -m pip_audit -r requirements.txt -r requirements-dev.txt --ignore-vuln CVE-2026-0994

security: security-backend

# secrets:
# 	@command -v gitleaks >/dev/null 2>&1 || { echo "gitleaks not installed. Install from https://github.com/gitleaks/gitleaks"; exit 1; }
# 	gitleaks detect --source . --no-git --redact --exit-code 1

# check: lint security secrets
check: lint security

hooks:
	git config core.hooksPath .githooks

docker-up:
	docker compose up --build

docker-down:
	docker compose down

sse-test:
	curl -N -X POST http://localhost:3000/v1/correct/stream -H "Content-Type: application/json" -d '{"text":"сина рәхмәт","lang":"tt","client":{"platform":"cli","version":"demo"}}'
