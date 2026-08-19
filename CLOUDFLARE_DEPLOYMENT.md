# Cloudflare Web Deployment

The Flutter web application is deployed with Cloudflare Workers Static Assets
behind the route-aware Worker in `cloudflare/worker.mjs`. The Worker name is
`animal-supply-b2b`. Direct Flutter routes such as `/invite?token=...` receive
the app shell, while missing static files return `404` instead of HTML.

## Current web deployment

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `6e4198f0-8979-4577-8011-45c5408be2e1`
- Git SHA: `69d81129937672cc3e62763146adde16d3c495b4` (`release/production-readiness-2026-08`)
- Flutter version: `1.0.4+5`
- Offline shell version:
  `web_shell_manifest.4018ff43cc4d6d6e.json`
- Runtime mode: `APP_ENV=production` against the linked Supabase project
- Firebase/web push: not configured (OS tray uses Service Worker `showNotification` while the tab/PWA can run; no Firebase keys were added)
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

This hostname now uses compile-time production mode and the public Supabase
URL/anon key. Staging demo logins (`admin`/`admin` overlay) are disabled.
Firebase public keys remain empty, so push delivery stays labelled
“not configured.” Keep `*.workers.dev` `noindex` until a custom domain and
client-approved catalog are accepted. Record the new version ID after every
release.

The August 19, 2026 Worker version `5429e4ef-fc78-47ef-8543-46dee3774d5b`
replaces the pull-to-refresh arrow morph with a frosted-glass HUD and ring
spinner, fixes an admin category refresh regression test, and ships offline shell
`web_shell_manifest.5487e61226f81784.json`.

The August 19, 2026 Worker version `24d2e03a-81ad-4c7f-b0eb-71ded6c71512`
redesigns admin إدارة المنتجات for routine ops without the full editor:
operational product cards with quick price/discount/stock sheets, featured and
visibility toggles with undo snackbars, filter shortcuts (العروض/المميزة/المخزون),
multi-select bulk discount and price adjustments, and preserved search/filter/sort/
pagination/full editor/archive flows; ships offline shell
`web_shell_manifest.8189797522ebfce6.json`.

The August 19, 2026 Worker version `687cf063-e633-4816-beaf-b89bc05e26a9`
adds a persisted 3-mode catalog view toggle on the customer المنتجات screen
(comfortable list, compact list, responsive grid), keeps RTL-safe controls near
search/filter, and ships the hashed offline shell
`web_shell_manifest.2e34f235359e1bd5.json`.

The August 19, 2026 Worker version `0cf9be73-ab8c-4948-9178-0a5a4bbe964c`
polishes the customer shell and home: a teal-gradient app bar with a white
logo disc and translucent circular WhatsApp/logout buttons, a typographic
greeting block with a full-width search pill, white category chips with
pastel icon discs, product cards with a gradient للسلة button and stronger
سعر الجملة hierarchy, and softer teal-tinted banner shadows, and ships the
hashed offline shell `web_shell_manifest.cfc8f9652024d426.json`.

The August 19, 2026 Worker version `78732df4-5eaa-4b7d-acdc-90c84ec5906e`
redesigns the cart screen: white line-item cards with `BoxFit.contain`
thumbnails, a grouped quantity stepper / line-total band, a dark-green
ملخص الطلب summary card, and a prominent sticky متابعة تأكيد الطلب bar,
and ships the hashed offline shell
`web_shell_manifest.9e8f5ac0a33a5541.json`.

The August 19, 2026 Worker version `5b086d04-12d0-4bb5-ae3d-3f29a61ac63c`
redesigns product details with a larger `BoxFit.contain` hero, grouped info
and wholesale-price cards (سعر الجملة in black), a sticky quantity / add-to-cart
/ WhatsApp bar, and ships the hashed offline shell
`web_shell_manifest.15357f8fa5633e6f.json`.

The August 19, 2026 Worker version `35a03363-80ea-4087-b6ae-d18cd94e38e7`
fits the customer-home first screen on a typical phone without vertical
scroll, uses a peeking PageView for banners and أحدث المنتجات with
`BoxFit.contain` photos, shows the product thumbnail in the add-to-cart
quantity sheet, paints سعر الجملة in near-black, and ships the hashed
offline shell `web_shell_manifest.15357f8fa5633e6f.json`.

The August 18, 2026 Worker version `c739a279-b457-4170-aa47-aefac3ee4e57`
labels the teal wholesale amount on customer-home and catalog product cards
as سعر الجملة, keeps بيع الوحدة / بيع الوحدة المقترح under it, and ships
the hashed offline shell `web_shell_manifest.4bfae53f8de847ef.json`.

The August 18, 2026 Worker version `0472d2c2-4517-43a4-a654-b58ca9470c9c`
enriches customer-home and catalog product cards with brand, pack size,
availability, wholesale price, and suggested unit price, and ships the hashed
offline shell `web_shell_manifest.deafb7277446f9a1.json`.

The August 18, 2026 Worker version `9c706d6b-7592-4e52-b906-a8eef495fffd`
redesigns customer-home latest-product cards (white bordered tiles, square
cover photos, two-line Arabic titles, inset add button) and ships the hashed
offline shell `web_shell_manifest.6a9de4233f925241.json`.

The August 18, 2026 Worker version `6047f6c2-58f4-4dc5-9dd7-0a963171d179`
stretches catalog list-card images to the full card height (RTL start
edge, clipped to the card corners) and ships the hashed offline shell
`web_shell_manifest.b7d0bec5a58a2408.json`.

The August 16, 2026 Worker version `e630c843-2e68-49fc-8c0a-14ceda0a6f1b`
improves checkout confirm-order hierarchy (grouped bordered text fields,
separated order review, darker estimated-total card, stronger green CTA)
and ships the hashed offline shell
`web_shell_manifest.250ab11d409d27d8.json`.

The earlier August 16, 2026 deployment was verified against the exact local
`main.dart.js`, contains a 76-resource content-hashed offline shell, and
loads a no-op `firebase_bootstrap.js`. Login uses real Supabase Auth.
Web product, banner, and logo uploads read file bytes in memory instead of
fetching a revoked `blob:` URL.

## Client-review demo

This build intentionally uses local demo data and does not connect to a remote
Supabase or Firebase project:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

/home/alnaagi/development/flutter/bin/flutter pub get
/home/alnaagi/development/flutter/bin/flutter analyze
/home/alnaagi/development/flutter/bin/flutter test

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_web_release.mjs \
  --release \
  --no-web-resources-cdn \
  --dart-define=APP_ENV=demo

cd /home/alnaagi/Desktop/animal_supply_b2b_app
npx --yes wrangler@4.121.0 deploy
```

The review hostname is intentionally sent with a `noindex` response header.
Do not remove the demo labels or make the site indexable until the real
catalog, client contact details, backend, and notification configuration are
approved.

The Worker is part of the release boundary. Validate it before deployment:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
node --test app/tool/*.test.mjs cloudflare/*.test.mjs
npx --yes wrangler@4.121.0 deploy --dry-run
```

## Production build

Copy the tracked example and enter only public client configuration:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
cp cloudflare.public.example.json cloudflare.public.json
```

`cloudflare.public.json` is ignored by Git. It may contain the Supabase anon
key and Firebase web client configuration because those values are delivered
to browsers by design. It must never contain a Supabase service-role key,
Firebase service-account JSON, private signing material, database passwords,
or any other server secret.

Build and deploy:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_web_release.mjs \
  --release \
  --no-web-resources-cdn \
  --dart-define-from-file=../cloudflare.public.json

cd /home/alnaagi/Desktop/animal_supply_b2b_app
npx --yes wrangler@4.121.0 deploy
```

Do not use a raw `flutter build web` for a release. The wrapper generates the
content-hashed shell manifest required by the app's atomic offline-update
service worker.

## Exact production-launch checklist

Complete every item before switching `APP_ENV` to `production`:

1. Obtain written approval for the client name, branding, support contacts,
   legal/delivery text, real catalog, prices, MOQ, stock, and licensed images.
2. Put the domain, Cloudflare zone, Supabase project, Firebase project, Apple
   account, Android signing backup, and billing under client-controlled
   ownership.
3. Back up any existing Supabase data. Run
   `supabase/production_preflight.sql`, resolve every finding, link the intended
   project, and apply the ordered migrations with `supabase db push`.
4. Disable public Auth sign-up and verify admin, staff, active customer,
   suspended customer, and archived customer behavior using real RLS
   integration tests. Do not continue if any client can bypass an Edge
   Function or read another customer's rows.
5. Configure only public values in `cloudflare.public.json`. Put service-role,
   notification-dispatch, Firebase service-account, and invite secrets only in
   Supabase Edge Function secrets.
6. Deploy every Edge Function listed in `supabase/README.md`; set the exact
   production origin in `ALLOWED_ORIGINS` (wildcards and implicit localhost
   access are rejected), a random server-only `RATE_LIMIT_SALT` of at least 32
   characters, the final HTTPS `/invite` URL in `INVITE_BASE_URL`, and the same
   real `CUSTOMER_LOGIN_DOMAIN` in Flutter and the functions.
7. Audit existing `product-images` objects before allowing public reads, then
   import only client-approved catalog data and image assets.
8. Configure Firebase Android, iOS/APNs, and web/VAPID values; schedule
   `dispatch-notification-outbox`; test order, targeted, broadcast, and
   product deep-link notifications on physical devices and the final web
   origin.
9. Build with the release wrapper, deploy to the final custom domain, and test
   login, forced password change, role redirects, invite links, ordering,
   admin transitions, customer updates, reload/deep links, service-worker
   upgrades, and offline reopen.
10. Keep the review hostname `noindex`. The Worker refuses to index
    `*.workers.dev` even if configured otherwise. Set the Cloudflare
    `ALLOW_INDEXING=true` environment variable only on the accepted custom
    domain and only after confirming no demo labels, placeholder contacts,
    sample prices, or test accounts are exposed.
11. Build Android and iOS through their platform handoff checklists and
    publish their controlled update destinations. For Android, insert matching
    `app_versions` metadata only after signature, version, URL, and checksum
    verification; iOS updates remain governed by TestFlight/App Store or the
    registered-device Ad Hoc process.
12. Deliver backups, recovery instructions, account ownership, monitoring,
    maintenance scope, and signed acceptance to the client.

## APK and custom domain

The signed APK and AAB are larger than the per-file limit for Workers Static
Assets and are not bundled into this web deployment. Enable Cloudflare R2 or
use another controlled download host, upload the signed APK, verify its
SHA-256 checksum, then set `APK_LINK` and the `app_versions.apk_url` value.

R2 is not enabled on the current Cloudflare account. The August 11, 2026
Wrangler preflight returned Cloudflare error `10042`. Enable R2 in the
Cloudflare dashboard or approve another client-controlled HTTPS artifact host
before publishing the direct APK link.

Use the permanent client domain before printing public QR codes or enrolling
users in web push notifications. Browser installs and push permissions are
tied to the exact web origin.

For iPhone/iPad distribution, the Cloudflare PWA can be shared immediately,
but a native `.ipa` cannot be installed by arbitrary customers from this
Worker or Google Drive. Follow `DEPLOYMENT_IOS.md`.

The 2026-08-19 17:30:49 EET (+0200) Worker version `0376346c-b843-487a-a649-baf3400979f0` is a final explicit deploy after stabilization.

The 2026-08-19 18:39 EET (+0200) Worker version `10f828fb-212f-47e0-a718-07c53d5c74be` deploys the focused order-completion integration: legacy `/order-success` URLs now redirect safely into `/orders`, checkout success navigates to `/orders?order=<id>&success=1` inside `CustomerShell`, and admin/customer invoice print + download now share a single canonical Arabic RTL PDF byte generator (`OrderInvoicePdf`) using `assets/fonts/NotoSansArabic-Variable.ttf`.

The 2026-08-19 19:16 EET (+0200) Worker version `34c006ae-ac57-4843-9606-7125cc7ebe61` deploys public-order-reference hardening: server-side random `AS-XXXXXXX` order references (with collision retry and secure backfill) plus admin reference normalization support (`AS-...`, lowercase, or prefix-less).

The 2026-08-19 20:07 EET (+0200) Worker version `ec5ad2fc-7c26-4d53-8c86-cc60a08dc6fa` deploys the focused Admin Banners UX redesign: compact management toolbar, modal store preview with mobile/desktop toggle, reorder-first compact cards with human-readable destinations, optimistic active toggle with rollback/undo, duplicate-banner flow, and live editor preview.

The 2026-08-19 21:45 EET (+0200) Worker version `6e4198f0-8979-4577-8011-45c5408be2e1` on branch `release/production-readiness-2026-08` (`69d8112`) ships production-readiness reconciliation: Supabase migrations for product discount constraints, customer device binding via `device_tokens.installation_id_hash`, random `AS-XXXXXXX` order references with legacy `AS-YYYYMMDD-NNNNNN` lookup preserved, admin password policy enforcement in Edge Functions, and offline shell `web_shell_manifest.4018ff43cc4d6d6e.json`.
