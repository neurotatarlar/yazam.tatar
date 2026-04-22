PYTHON ?= python3
WEB_BASE_HREF ?= /
WEB_API_BASE_URL ?= http://127.0.0.1:3000


install:
	$(PYTHON) -m pip install -r requirements.txt

install-dev:
	$(PYTHON) -m pip install -r requirements-dev.txt

client-deps:
	@echo "Static web client has no dependency install step."

dev: client-deps
	@bash -c 'set -euo pipefail; \
	trap "kill 0" EXIT INT TERM; \
	WEB_BASE_HREF="$(WEB_BASE_HREF)" API_BASE_URL="$(WEB_API_BASE_URL)" BUILD_SHA=dev ./deploy/build_web_static.sh build/web-dev; \
	$(PYTHON) -m uvicorn backend.main:app --reload --port $${PORT:-3000} & \
	$(PYTHON) -m http.server --directory build/web-dev 8080'

test-backend:
	$(PYTHON) -m pytest

test-client: client-deps
	$(PYTHON) tools/check_web_static.py

test: test-backend test-client

lint-backend:
	$(PYTHON) -m ruff check backend
	$(PYTHON) -m ruff format --check backend
	$(PYTHON) -m mypy backend

lint-client: client-deps
	$(PYTHON) tools/check_web_static.py

lint: lint-backend lint-client

lint-fix:
	$(PYTHON) -m ruff check backend --fix
	$(PYTHON) -m ruff format backend
	@echo "No static web auto-fix configured."

format-backend:
	$(PYTHON) -m ruff format backend

format-client:
	@echo "No static web formatter configured."

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
