# Cloudflare Web Deployment

The Flutter web application is deployed with Cloudflare Workers Static Assets
behind the route-aware Worker in `cloudflare/worker.mjs`. The Worker name is
`animal-supply-b2b`. Direct Flutter routes such as `/invite?token=...` receive
the app shell, while missing static files return `404` instead of HTML.

## Current client-review deployment

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `770b7a01-6575-49e9-8ca7-b77f393c8f5b`
- Flutter version: `1.0.4+5`
- Offline shell version:
  `2a1f208c897592533cfeb8affdf5ed6ff72bcdb211181feaad6fd8066b91089a`
- Runtime mode: `APP_ENV=demo`
- Search indexing: blocked intentionally with
  `X-Robots-Tag: noindex, nofollow, noarchive`
- Edge controls: HTTP-to-HTTPS redirect, HSTS, CSP, frame denial, MIME
  protection, permissions policy, and fresh-cache rules for the app shell

This URL is a review build. It has no production Supabase or Firebase
connection, uses labelled demo data, and must not be represented as the
client's live ordering system. A later deployment can replace this Worker
version; record the new version ID in the handoff after every release.

The August 13, 2026 deployment was verified against the exact local
`main.dart.js` and `flutter_bootstrap.js`, and the release contains a
76-resource content-hashed offline shell. Eligible Chromium browsers receive
an Arabic prompt connected to the native PWA install confirmation, while
iPhone/iPad Safari receives Add to Home Screen instructions. The prompt stays
hidden in an installed standalone window and remembers a dismissal for seven
days. The final deployment passed
direct-route fallback, static-file `404` behavior, security/no-cache headers,
Arabic RTL rendering, customer demo login, and the customer home/catalog
screen. The full Flutter and release-guard suites cover the remaining customer
and admin workflows.

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
