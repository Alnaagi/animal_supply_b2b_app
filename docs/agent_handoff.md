# Current State
- Current phase: Offline persistence (durable cart/catalog/outbox)
- Last verified commit: pending (this unit)
- Working tree: dirty — large prior Codex production-readiness work remains uncommitted
- Completed: Secure order flow (place-order/transition), auth/invite/notifications scaffolding, migrations, iOS scaffold, demo catalog fixes (uncommitted Codex work); durable LocalCache/SyncOutbox + cart hydrate/outbox enqueue (this unit)
- Partially completed: Docs/example config update (Codex announced, no patches); brand icon replacement deferred
- Not started: Auto-retry outbox on reconnect; full release/deploy verification; docs sync

# Validation
- Commands passed: `dart format` (unit files); `flutter test test/cart_controller_test.dart` (3/3); `flutter analyze` (unit files, no issues)
- Commands failed: none for this unit
- Commands not run: full `flutter test`, release builds, Supabase deploy

# Next Exact Task
- Wire connectivity-triggered outbox retry that re-invokes `place-order` with stored product_id/quantity + client_request_id only (no client prices).

# Important Risks
- Large unverified uncommitted Codex surface still outside this commit.
- Outbox does not auto-flush yet; user must retry checkout manually.
- Cached catalog prices are display estimates only.
- Live E2E needs deployed migrations + Edge Functions.
- Do not commit signing keys, `.env`, or Firebase service accounts.
