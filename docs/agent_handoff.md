# Current State

- Status date: August 14, 2026.
- Current phase: production activation and final release packaging.
- The production-hardening pass is still in a dirty working tree. Preserve and
  review it; do not reset or selectively discard unrelated changes.
- Completed: Arabic RTL app shell, protected authentication/invites, forced password
  change, authoritative server-side ordering, status history, inventory
  reservations, offline cart/catalog cache, idempotent order outbox retry,
  in-app/push notification queueing, admin campaigns, release update metadata,
  app icons, Android signing, and iOS project scaffolding.
- Completed in the latest pass: customer/product administration,
  customer-wide discounts managed from the customer profile, retirement of the
  standalone price-group/per-product pricing surface, banners, controlled
  product-image upload,
  campaign audience mapping, staff route restrictions, maintenance-mode order
  block, timed outbox retry, update-safe web service worker behavior, exact
  browser-origin enforcement before Edge side effects, production
  `RATE_LIMIT_SALT` fail-closed behavior, request-bound order idempotency,
  reservation-aware stock visibility, invite-gated account activation,
  locked-account device-token revocation, aggregate dashboard/report RPCs,
  bounded customer/order/catalog paging, server-side catalog facets,
  platform-aware Android/iOS update administration, notification permission
  recovery, responsive dialogs, accessibility labels, and native launch
  resources.
- Completed in the current product pass: a simplified Arabic product editor,
  wholesale-only order pricing, suggested retail-unit reference pricing, bulk
  MOQ, optional units-per-box metadata, independent visibility/archive
  controls, tracked/untracked inventory, configurable out-of-stock visibility,
  order-item snapshots, matching customer catalog/cart/order presentation, and
  migration `202607220031_simplified_product_controls.sql`.
- Completed in the final release pass: durable outbox deletion/rollback,
  corrupt-cache quarantine, exact unread notification counts, fail-closed
  remote password reset, role-aware push destinations, protected notification
  payload fields, order-transition timeout mapping, validated Android update
  metadata, a public Arabic `/download` page, mobile artifact/secret scanning,
  fail-safe Cloudflare indexing controls, admin-only owned banner storage, and
  fail-closed audit logging for privileged customer/invite/password actions.
- Live review build:
  `https://animal-supply-b2b.alnaagi-ai.workers.dev`
  (Cloudflare version `770b7a01-6575-49e9-8ca7-b77f393c8f5b`).
  It is an intentionally `noindex` demo build with no production backend.
- The web release now captures the browser PWA install event before Flutter
  starts and shows an Arabic RTL install dialog after the app is ready.
  Chromium uses the native install prompt; iPhone/iPad Safari shows
  Add to Home Screen instructions.

# Validation

- Passed: `flutter analyze`
- Passed: `flutter test` (187 tests)
- Passed: browser-platform foreground notification test in Chrome.
- Passed: Deno formatting, type checking, linting, and 30 function tests.
- Passed: 28 Node release-guard, PWA-install, mobile-release, service-worker,
  and Cloudflare
  Worker tests.
- Passed on July 23, 2026: isolated local Supabase/PostgreSQL application of
  all 18 migrations
  through `202607220031`, the seed, migration-031 product/inventory behavior
  and activation/delivery security suites, `production_preflight.sql` with
  zero blockers, expected constraints and function grants, and database lint
  with no schema errors. Docker was unavailable for rerunning this database
  suite on August 11; the client-hosted staging project remains untested.
- Passed: catalog RPC runtime checks for authenticated-only execution,
  `SECURITY INVOKER`, inactive-product role behavior, unknown-user denial,
  RLS coverage, customer pricing boundaries, and reservation-aware stock.
- Passed: credential-shaped secret scans across the final web, APK, and AAB
  outputs; no signing files or private configuration were packaged.
- Passed: offline-ready web release wrapper and deterministic
  `--prepare-only` shell-manifest verification, including a production-like
  public-config compile followed by a clean explicit demo rebuild.
- Passed: route-aware Cloudflare Worker tests, HTTPS redirect, HSTS/CSP
  headers, real static-file `404` behavior, direct route fallback, complete
  76-resource offline-shell generation, final deployed/local
  `main.dart.js`/`flutter_bootstrap.js`/`pwa_install.js` matching, and live
  version `1.0.4+5` verification.
- Passed: Arabic/RTL widget coverage, route-role matrix, and responsive banner
  overflow regression. Fresh release-browser checks covered mobile
  `390x844`, tablet `768x1024`, and desktop `1440x900`, including protected
  admin routing, admin orders, notification campaigns, customer catalog,
  cart, checkout, and a successful demo order without console errors or
  horizontal overflow.
- Passed on the final live deployment: customer demo login, catalog, MOQ cart,
  checkout, demo order `DEMO-1003`, customer order history, admin role routing,
  admin order status transition to confirmed, and notification-campaign page.
- Passed: fresh signed Android demo APK/AAB build through the guarded mobile
  release wrapper, APK Signature Scheme v2 verification, APK alignment, AAB
  JAR/ZIP validation, matching long-term certificate, Gradle signing
  validation, Arabic installed label, release-manifest generation, and
  credential-shaped secret scanning.
- Not available on this Fedora host: iOS archive/signing. Build on macOS/Xcode
  using the client-owned Apple team.

# Review Deployment

- Web review URL:
  `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `770b7a01-6575-49e9-8ca7-b77f393c8f5b`
- Offline shell:
  `2a1f208c897592533cfeb8affdf5ed6ff72bcdb211181feaad6fd8066b91089a`
- Environment: demo/offline-friendly review, not production
- Indexing: intentionally disabled

# Release Artifacts

- Web: deployed review version `1.0.4+5` above.
- Demo APK:
  `app/build/app/outputs/flutter-apk/app-release.apk`
- APK SHA-256:
  `cc2ff2954d9e082b440ef6472b07260ee2fea07412c25eed6648cc692ccc1b66`
- Demo AAB:
  `app/build/app/outputs/bundle/release/app-release.aab`
- AAB SHA-256:
  `83f0154fbc402228ad0cf1e2e6d4b34b5a9500377bf8317cf5a814f4b1797bff`
- Android package/version: `ly.animalsupply.b2b`, `1.0.4` (`versionCode 5`)
- Android artifact sizes: APK `61,424,761` bytes; AAB `48,192,356`
  bytes.
- Release manifest:
  `app/build/release-manifests/android-1.0.4+5.json`
- Release manifest SHA-256:
  `ef06d09e759fe2f6f4f34beef8ed05e22d186b175075147f5954b97c5dd6837f`
- Signing certificate SHA-256:
  `C0:F6:8C:B3:06:7D:D4:FB:64:AA:50:D1:C8:00:2A:21:BC:EC:DA:DE:B4:DA:DD:A3:75:8E:43:5B:7D:11:0C:53`
- These are demo-mode artifacts. Rebuild and record new hashes after inserting
  approved production Supabase/Firebase public configuration.
- iOS IPA/archive: not produced on Fedora.

# Next Exact Task

1. Run `supabase/production_preflight.sql` against a backup/current snapshot,
   resolve its findings, link the client Supabase project, run
   the complete 19-migration chain through `202608020032`, and deploy every
   function listed in
   `supabase/README.md`.
2. Configure production Edge secrets, exact origins/login domain, Firebase,
   APNs, web push, a scheduled notification dispatcher, and the final
   client-controlled domain/download URLs.
3. Perform the full RLS role matrix and end-to-end order/notification tests
   against staging before importing the approved production catalog.
4. Rebuild/sign Android in production mode with the same long-term key, verify
   the signature, record fresh checksums, and publish the APK through a
   controlled HTTPS host. Cloudflare R2 is not enabled on the current account
   (`10042`), and the APK/AAB exceed Workers Static Assets' per-file limit.
5. Build and distribute iOS on macOS through TestFlight or registered-device
   Ad Hoc provisioning; use the PWA for immediate link-based iPhone access.
6. Follow the complete checklist in `CLOUDFLARE_DEPLOYMENT.md`, then obtain
   written client acceptance before treating any deployment as production.

# Important Risks

- Catalog data, sample image URLs, and prices remain demo content until the
  client approves and imports the real catalog. The image-upload workflow
  itself is implemented.
- Cached catalog prices are display estimates only; the Edge Function remains
  authoritative.
- The active pricing contract is the customer's optional all-products
  `discount_percent`, managed from the customer profile and resolved
  server-side. `products.discount_percent` remains product-promotion metadata,
  not the customer discount.
- Legacy `price_groups`, `product_prices`, and `customer_special_prices` remain
  dormant for transition compatibility and must not influence active pricing.
  Do not delete their existing rows without a separately approved migration and
  backup. Existing orders retain their immutable unit-price snapshots.
- Outbox entries are account-scoped, retry independently with capped backoff,
  and quarantine legacy unowned entries; durable storage failure is surfaced
  instead of falsely promising a saved offline order.
- Migration/RLS behavior passed in an isolated local runtime but has not yet
  been repeated against the client-hosted staging project. Migration `032`
  was added after that local database run and must be applied/preflighted on
  staging.
- Migrations `028`-`031`, the customer-discount transition, authentication,
  RLS, order transactions, catalog pricing, and release signing should receive
  a final isolated GPT-5.6 Sol High review before the production backend is
  activated.
- Real push delivery remains blocked by client Firebase/APNs/web configuration.
- Required/optional native update prompts are implemented, but minimum app
  version is not an API/RLS security boundary; a modified or metadata-offline
  client is not rejected server-side by build number.
- Cloudflare R2 is currently disabled, so the signed APK still needs an
  approved controlled HTTPS host before the download/update button can be
  activated.
- The Workers review URL is not a native-app download host and is not the
  final indexed production domain.
- Do not commit signing keys, `.env`, Firebase service accounts, or Supabase
  service-role credentials.
