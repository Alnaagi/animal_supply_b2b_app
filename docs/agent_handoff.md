# Current State
- Current phase: Offline persistence (outbox auto-retry)
- Last verified commit: pending (this unit)
- Working tree: dirty — large prior Codex production-readiness work remains uncommitted
- Completed: Durable LocalCache/SyncOutbox; connectivity-triggered place-order outbox flush (product_id/quantity + client_request_id only)
- Partially completed: Docs/example config update; brand icon replacement deferred; home banner stutter fix (uncommitted)
- Not started: Full release/deploy verification; docs sync with live env examples

# Validation
- Commands passed: `dart format` (unit files); `flutter test test/outbox_retry_test.dart test/cart_controller_test.dart` (4/4); `flutter analyze` (unit files)
- Commands failed: none for this unit
- Commands not run: full `flutter test`, release builds, Supabase deploy

# Next Exact Task
- Align repository setup/release docs and `.env.example` with the implemented auth, order, notification, and offline flows (no secrets).

# Important Risks
- Large unverified uncommitted Codex surface still outside commits.
- Outbox flush stops on first failure in the queue (intentional backoff).
- Cached catalog prices remain display estimates only.
- Live E2E needs deployed migrations + Edge Functions.
- Do not commit signing keys, `.env`, or Firebase service accounts.
