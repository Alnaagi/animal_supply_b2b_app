# Current State

- Current phase: production-readiness implementation and release validation.
- Last committed baseline: `3a370e1`; the larger hardening pass remains intentionally
  uncommitted for review.
- Completed: Arabic RTL app shell, protected authentication/invites, forced password
  change, authoritative server-side ordering, status history, inventory
  reservations, offline cart/catalog cache, idempotent order outbox retry,
  in-app/push notification queueing, admin campaigns, release update metadata,
  app icons, Android signing, and iOS project scaffolding.
- Completed in the latest pass: valid campaign audience mapping, staff route
  restrictions for admin-only operations, maintenance-mode order block, web
  update-safe service worker behavior, release/deployment documentation, and
  Android release artifact validation.

# Validation

- Passed: `flutter analyze`
- Passed: `flutter test` (20 tests)
- Passed: `flutter build web --release`
- Passed: `flutter build apk --release`
- Passed: `flutter build appbundle --release`
- Passed: APK signature verification with Android `apksigner` (v2 signature).
- Manual release-web demo path passed: customer catalog -> MOQ/cart -> checkout ->
  order `DEMO-1003` -> admin queue -> confirmation transition.
- Manual release-web role check passed: staff navigation hides admin-only
  broadcast/settings routes and a direct broadcast URL redirects to `/admin`.
- Not run: Supabase migration execution/RLS integration test because no local
  PostgreSQL/Supabase database is running.
- Not run: iOS build/archive because this Fedora Flutter SDK exposes no iOS
  build target; archive on macOS/Xcode using the client Apple team.

# Release Artifacts

- APK: `app/build/app/outputs/flutter-apk/app-release.apk`
- AAB: `app/build/app/outputs/bundle/release/app-release.aab`
- APK SHA-256:
  `072c504435b26f291f4e40303a9fd7ac91b43efe1f4b9565ea923eafcea7346c`

# Next Exact Task

1. Create/link the client Supabase project, run `supabase db push`, then deploy
   every function listed in `supabase/README.md`.
2. Configure production Edge secrets, Firebase/APNs/Web Push values, a
   scheduled notification dispatcher, and the real HTTPS download/domain URLs.
3. Perform RLS integration tests against the deployed project before importing
   client data.

# Important Risks

- Catalog data, images, and prices are still marked demo/placeholder until the
  client approves and imports the real catalog.
- Cached catalog prices are display estimates only; the Edge Function remains
  authoritative.
- Outbox flush intentionally stops after the first failed entry to preserve
  ordering and backoff.
- Do not commit signing keys, `.env`, Firebase service accounts, or Supabase
  service-role credentials.
