# Engineering AGENTS Guide

This file defines frontend and backend rules for this repository.

## Scope

- Frontend web code lives in `webapp/` (HTML/CSS/JS).
- Shared frontend assets and i18n live in `client/assets/`.
- Legacy Flutter code in `client/lib/` is reference-only and not part of deployment.
- Product type: grammar correction tool (GEC), not open-ended chat.
- Backend code lives in `backend/`.

## Adopted Reference (Anthropic frontend-design skill)

Only the following parts are adopted for this project:

1. Intentional design direction.
- Every UI change should have a clear purpose and visual rationale.

2. High-quality typography and color decisions.
- Keep typography readable and purposeful.
- Keep a coherent palette; reuse existing constants/tokens first.

3. Meaningful motion only.
- Motion should communicate state (loading, transitions), not decoration.

4. Avoid generic AI-looking UI defaults.
- Do not ship interchangeable chat-like visuals for correction workflows.

## Adopted Reference (Kotlin kotlin-agent-skills)

Only transferable backend ideas are adopted from:

- `kotlin-backend-jpa-entity-mapping`
- `kotlin-tooling-java-to-kotlin`

Applicable principles used here:

1. Preserve behavior during refactors.
- Make incremental changes.
- Verify behavior with tests and static checks before finishing.

2. Keep model boundaries explicit.
- Keep API transport schemas separate from internal runtime/persistence structures.
- Avoid coupling request/response models to storage internals.

3. Enforce invariants at multiple layers.
- Validate at API boundary for clear user-facing errors.
- Enforce correctness in storage/constraints where applicable.

4. Measure performance, do not guess.
- Diagnose bottlenecks with observable signals (latency, query count, logs, metrics).
- Use targeted fixes instead of broad, annotation-style guesswork.

## Project-Specific UX Rules

1. Correction framing is mandatory.
- Primary mental model: `Original text -> Correction`.
- Never label output as "Answer".
- Avoid assistant persona signals unless explicitly requested.

2. Clarity over novelty.
- Labels and actions must be explicit and task-specific.
- Keep primary actions obvious: correct, copy, replace, retry, clear.

3. History is utility, not dialogue.
- Preserve history for reuse.
- Do not imply the app supports free-form assistant conversation.

## Flutter Implementation Rules

- Legacy-only: apply these rules only when touching reference Flutter code under `client/lib/`.

## Backend Rules

1. API contract stability.
- Keep endpoint shapes explicit and stable (`/v1/correct`, `/v1/correct/stream`).
- Preserve documented SSE event names and semantics (`meta`, `delta`, `done`, `error`).
- Return structured errors; do not leak internal stack traces in responses.

2. Validation and limits.
- Enforce request validation early (content type, JSON shape, text limits, body size).
- Keep rate limiting and concurrency guards explicit and test-covered.

3. Reliability and observability.
- Keep metrics and counters aligned with request outcomes.
- Keep logging metadata-focused and avoid logging full user text by default.
- Update status/health/version endpoints when runtime behavior changes.

4. Data and idempotency (if persistence is introduced).
- Apply DB constraints for correctness (e.g., uniqueness).
- Keep application-level checks for user-friendly errors.
- Treat app checks and DB constraints as complementary, not substitutes.

5. Security hygiene.
- No secrets in code, tests, fixtures, or committed config files.
- Keep dependency and security checks in normal workflow.

## i18n and Copy

- No hardcoded user-facing strings in widgets.
- Add every new key to:
  - `client/assets/i18n/en.json`
  - `client/assets/i18n/ru.json`
  - `client/assets/i18n/tt.json`
- Use consistent correction terminology (`Original`, `Correction`, `Correcting`).

## Accessibility and Quality

- Keep contrast and tap targets accessible.
- Preserve keyboard usability where practical.
- Do not encode meaning by color only.

## Validation Before Finish

- `cd client && /home/tans1q/flutter/bin/flutter analyze --no-version-check`
- `make test-client`
- Verify no regression in: streaming, retry, copy, report, history.
- `.venv/bin/python -m ruff check backend`
- `.venv/bin/python -m mypy backend`
- `make test-backend`
- `make security-backend`
