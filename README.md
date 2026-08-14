# Animal Supply B2B

Arabic-first Flutter MVP for a B2B animal food, feed, farm supply, and pet supply shop. Customers cannot self-register; admin or staff creates accounts and sends a WhatsApp invite with username, temporary password, app download link, and an invite link that contains only a token/client code.

## Assumptions

- One Flutter app serves customers, staff, and admin using role-based routing.
- Supabase Auth users are created by Edge Functions, never directly from the public client.
- Current code runs in demo mode if Supabase env vars are not provided.
- Currency is LYD and UI defaults to Arabic RTL.
- Android APK sideloading is part of MVP distribution.

## Run

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app
flutter pub get
flutter run
```

With Supabase:

```bash
flutter run \
  --dart-define=APP_ENV=staging \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=CUSTOMER_LOGIN_DOMAIN=accounts.YOUR_CLIENT_DOMAIN
```

The same `CUSTOMER_LOGIN_DOMAIN` must be configured as a Supabase Edge
Function secret. Placeholder domains are rejected in production builds.

## Demo Logins

- Admin: `admin@demo.ly` / `Admin123!`
- Staff: `staff@demo.ly` / `Staff123!`
- Customer: `tripoli-pets` / `Customer123!`

## Supabase Setup

This project is migration-first. `schema.sql` is a legacy reference and
`rls.sql` intentionally fails closed; deploy only the ordered migrations.

1. Create and link a Supabase project.
2. For a fresh project, run `supabase db push`. For an existing project already
   migrated through `024`, run
   `supabase/legacy_constraints_preflight.sql` before migration `027`. If a
   push stops on migration `027`, repair every reported legacy-data conflict
   and retry; do not skip the validation migration. After migration `032`,
   run `supabase/production_preflight.sql` for the complete production check.
3. Review the `product-images` Storage bucket and its ownership/admin RLS
   policies created by the migrations before importing approved images.
4. Configure Edge Function secrets and deploy the functions listed in
   `supabase/README.md`.
5. Keep public Auth sign-up disabled. Customers are created only by the
   secured admin/staff Edge Functions.

## Android APK

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app

flutter build apk --debug

FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_mobile_release.mjs android \
  --dart-define-from-file=../mobile.public.json
```

See `DEPLOYMENT_ANDROID_APK.md`, `DEPLOYMENT_IOS.md`, and
`MOBILE_APK_TESTING_AND_UPDATES.md` for signing, direct download flow, app
version checks, push setup, and platform limitations.

For the Flutter web release, Cloudflare Workers Static Assets configuration
is included in `wrangler.jsonc`. See `CLOUDFLARE_DEPLOYMENT.md` for the
review-safe demo deployment and the production configuration checklist.

Current client-review deployment:

- URL: `https://animal-supply-b2b.alnaagi-ai.workers.dev`
- Cloudflare version: `770b7a01-6575-49e9-8ca7-b77f393c8f5b`
- App version: `1.0.4+5`
- Status: demo data, no production Supabase/Firebase connection, and
  intentionally `noindex`; this is not the production launch.
- Eligible browsers now receive an Arabic install-as-web-app prompt after the
  app loads. Chromium uses its native install confirmation; iPhone/iPad Safari
  receives Add to Home Screen guidance.

## MVP Limitations

- Demo mode remains intentionally available without Supabase credentials;
  production workflows require a migrated client-owned Supabase project.
- Offline support persists catalog/cart data and safely retries unsent orders
  using product IDs and quantities only; the server remains authoritative for
  prices, stock, and account status.
- An optional customer-wide discount is managed from the customer's admin
  profile and resolved by the server for every product. The product-level
  `products.discount_percent` field remains catalog-promotion metadata and is
  not the customer's negotiated discount.
- Legacy price-group, group-price, and per-product special-price tables remain
  dormant during the transition for compatibility and audit safety. They are
  not exposed by the active admin UI, and existing orders retain their original
  immutable price snapshots.
- Admin product-image upload is implemented for approved JPEG, PNG, and WebP
  files through the controlled `product-images` Supabase Storage bucket.
  Demo catalog images remain placeholders until the client supplies licensed
  production assets.
- Password reset, Auth user creation, invite redemption, password completion,
  device-token registration, order transactions, and privileged status changes
  remain Edge Function operations in production.
- Firebase Cloud Messaging needs a client-owned Firebase project, platform
  configuration, APNs setup for iOS, web VAPID configuration, and a scheduled
  Supabase dispatcher before actual push delivery is enabled.

## Admin Operations Phase

- Admin UI is responsive inside the same Flutter app.
- Customer profiles, including customer-wide discounts, plus product, banner,
  order, settings, app-update, and notification operations are
  repository-backed.
- When Supabase env vars are configured, admin writes use Supabase tables/RLS and Edge Functions for secure Auth operations.
- Normal APK apps cannot silently self-update. Required/optional signed APK
  update prompts are implemented. Shorebird is only an optional future channel
  and is not currently configured or included in the release promise.

## Phase 2A UI Demo

The customer flow now includes modern Arabic shopping screens: home offers, category circles, searchable catalog, product details, cart totals, checkout, order history, reorder, and fast demo login buttons. See `UI_UX_UPGRADE_NOTES.md`.

## Demo Catalog Notice

The product catalog contains realistic sample names, common brand references, placeholder images, stock values, and LYD demo prices for presentation/testing only. It must be replaced with the client-approved catalog before production.

الأسعار الموجودة في النسخة التجريبية افتراضية وليست أسعار بيع فعلية.

See `DEMO_PRODUCT_CATALOG_NOTES.md` and `docs/product_import_template.csv`.
