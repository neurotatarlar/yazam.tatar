# Test Plan

## Backend API (current coverage)
- [x] Health endpoint
- [x] Version endpoint
- [x] Status endpoint
- [x] Metrics endpoint
- [x] Validation errors (empty/too long)
- [x] Rate limiting (minute/day)
- [x] Cache hit and cached stream result
- [x] Streaming events (meta/delta/done)
- [x] Streaming error event
- [x] Metrics after stream
- [x] Active stream status aggregation
- [x] Stream concurrency guard (per IP)

## Backend API (add)
- [x] Validation boundaries (exact max chars, whitespace-only, missing lang)
- [x] Cache TTL expiry (evicts after TTL)
- [x] Cache key includes lang (same text different lang not shared)
- [x] Streaming event ordering contract (meta first, done last, no extra after done)
- [x] Error mapping consistency for stream + non-stream (500 shape and metrics)
- [x] Rate limit reset behavior (minute/day windows)
- [x] Rate limiting per-IP isolation (one IP throttled, another allowed)
- [x] Rate limit burst behavior (short burst hits 429 predictably)
- [x] Client IP parsing for x-forwarded-for multi values
- [x] OpenAPI schema smoke test (endpoint reachable)

## Backend internals (add)
- [x] SSE formatting (json escaping, newlines, comments)
- [x] SSE injection safety for newline/crlf inputs
- [x] Settings/env parsing fallbacks (invalid values)
- [x] Concurrency guard is per IP, not global
- [x] Metrics increments once per request outcome

## Streaming integration (add)
- [x] Real ASGI server streaming test (verify active_streams > 0 during open stream)
- [x] Concurrent stream load smoke test (open N streams, ensure 429 on N+1)

## Web Client (add)
### Unit tests
- [ ] Backend client SSE parsing (delta assembly + done)
- [ ] Error handling mapping (server error, rate limit)
- [ ] App state transitions (input -> stream -> output)
- [ ] Settings persistence (browser storage)
- [ ] History persistence (browser storage)
- [x] Config loading (base URL, app name, identifiers)
- [x] Layout state machine (horizontal/vertical, expand/collapse)
- [ ] Stream lifecycle (start/stop/cancel) state transitions
- [x] Config fallback when config file missing/empty
### UI tests
- [x] Offline view rendering when backend unreachable
- [x] Widget flow: input -> stream -> output populated
- [x] Layout toggle updates panels (horizontal/vertical)
- [x] Expand/collapse panel fills available space
- [x] Copy button copies text and shows feedback
- [x] Corrected panel is read-only but selectable
- [x] Error banner/snackbar renders for 429/500
- [ ] Responsive layout across breakpoints (mobile/tablet/desktop)

## End-to-end (add)
- [x] Minimal e2e smoke test (backend + client, stream -> output)
- [ ] Full stack e2e (run backend + web client, drive UI and verify output)
- [x] CLI smoke test (curl SSE, verify meta/delta/done)

## Test tooling (add)
- [x] Test markers/tags (fast vs integration/slow)

## Contract (add)
- [x] SSE schema contract test (event names + payload shapes)
- [x] REST schema contract test (error shapes and validation)

## Performance & load (add)
- [ ] Concurrency soak (open N streams, monitor memory/FD growth)
- [ ] 10 RPS with 60s latency (backend CPU/memory baseline)
- [ ] Web client under network throttling (slow 3G/4G)
- [ ] Low-end device profile (CPU/memory) for web runtime

## Resilience (add)
- [ ] Network drop mid-stream (client recovers gracefully)
- [ ] Backend timeout (client shows error state)
- [x] Rate limit abuse (sustained 429s, no crashes)

## Security (add)
- [x] Input fuzzing for validation (unicode, large payload)
- [x] Basic header checks (cache-control, content-type, cors)
- [x] Content-type enforcement (reject non-JSON)
- [x] Payload size limits (oversized body rejected)

## Model usage guardrails (add)
- [x] Max chars enforced for stream and non-stream
- [x] Concurrency limit enforced per IP
- [x] Rate limit cannot be bypassed via x-forwarded-for chain
- [x] Invalid lang handling (default or reject consistently)
- [x] Response metadata does not leak prompt/config

## Accessibility (add)
- [ ] Keyboard focus order (web)
- [ ] Screen reader labels for controls (web)
- [ ] High-contrast readability check (web)

## Visual regression (add)
- [ ] Baseline screenshots for key states
- [ ] Screens for horizontal/vertical layouts
- [ ] Screens for expanded panel state
- [ ] Screens for error/offline states

## Localization (add)
- [ ] Tatar glyph rendering on system fonts
- [ ] Non-ASCII input handling in UI (copy/select)

## Data migration (add)
- [ ] Browser storage migration (history/settings)
