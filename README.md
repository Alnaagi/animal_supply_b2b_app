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
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=APP_DOWNLOAD_LINK=https://example.com/animal-supply.apk
```

## Demo Logins

- Admin: `admin@demo.ly` / `Admin123!`
- Staff: `staff@demo.ly` / `Staff123!`
- Customer: `tripoli-pets` / `Customer123!`

## Supabase Setup

1. Create a Supabase project.
2. Run `supabase/schema.sql`.
3. Run `supabase/rls.sql`.
4. Run `supabase/seed.sql` after creating matching Auth users or through the Edge Functions.
5. Create Storage bucket `product-images` and keep it private or public-read with controlled writes.
6. Deploy functions in `supabase/functions`.

## Android APK

```bash
cd app
flutter build apk --debug
flutter build apk --release
```

See `DEPLOYMENT_ANDROID_APK.md` and `MOBILE_APK_TESTING_AND_UPDATES.md` for signing, direct download placeholders, app version checks, Shorebird OTA notes, and Android sideloading limitations.

## MVP Limitations

- Demo repositories are in-memory until Supabase credentials and remote repositories are connected.
- Offline support includes connectivity banner, repository boundaries, and cache/outbox placeholders; full conflict-safe sync is Phase 2.
- Product image upload UI is a placeholder.
- Password reset and Auth user creation must happen via Edge Functions in production.
- Firebase Cloud Messaging client setup requires a Firebase project and Android `google-services.json`; server-side notification scaffolding is present in Supabase functions.

## Admin Operations Phase

- Admin UI is responsive inside the same Flutter app.
- Customer, product, order, settings, APK update, and notification scaffolding are repository-backed.
- When Supabase env vars are configured, admin writes use Supabase tables/RLS and Edge Functions for secure Auth operations.
- Normal APK apps cannot silently self-update. This project uses signed APK update prompts plus planned Shorebird OTA for Flutter/Dart-only patches.

## Phase 2A UI Demo

The customer flow now includes modern Arabic shopping screens: home offers, category circles, searchable catalog, product details, cart totals, checkout, order history, reorder, and fast demo login buttons. See `UI_UX_UPGRADE_NOTES.md`.

## Demo Catalog Notice

The product catalog contains realistic sample names, common brand references, placeholder images, stock values, and LYD demo prices for presentation/testing only. It must be replaced with the client-approved catalog before production.

الأسعار الموجودة في النسخة التجريبية افتراضية وليست أسعار بيع فعلية.

See `DEMO_PRODUCT_CATALOG_NOTES.md` and `docs/product_import_template.csv`.
