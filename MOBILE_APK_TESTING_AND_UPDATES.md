# Mobile APK Testing, Updates, And Notifications

## Distribution Choice

This project supports controlled direct Android APK distribution for testing
and a client pilot. The app is not assumed to be on Google Play.

Recommended setup:

1. Build a signed release APK.
2. Host it at the configured `APK_LINK`.
3. Add the newest version row to Supabase `app_versions`.
4. The app opens the APK link when an update is available.

Android will still ask the user to approve installing apps from that source. A normal APK app cannot silently replace itself unless the devices are managed through device-owner/MDM style controls.

## Build Commands

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
cp mobile.public.example.json mobile.public.json

cd app
flutter build apk --debug
FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_mobile_release.mjs android \
  --dart-define-from-file=../mobile.public.json
```

Release updates require:

- Same Android package name.
- Same signing key.
- Higher `versionCode`.
- Fresh wrapper-generated release manifest, checksum, and secret scan.

## Update Strategy

Use a hybrid strategy:

- Optional Shorebird OTA: possible Flutter/Dart/UI patches only after a
  separate Shorebird setup, validation, and commercial decision. Shorebird is
  not currently configured or promised by this release.
- Signed APK update: native plugins, permissions, Firebase config, app icon, Android manifest, package/signing, or anything Shorebird cannot patch.
- Supabase `app_versions`: controls latest APK URL, release notes,
  optional/required update flags, checksum, and artifact size. Android
  publication is rejected unless the URL is HTTPS, the SHA-256 is present,
  and the file size is positive.

The required-update gate is a native client control: it becomes
non-dismissible only when published metadata requires the installed build to
update and includes a valid HTTPS destination. It intentionally does not trap
users when metadata is temporarily unavailable or invalid. The current Edge
Functions and PostgREST policies do not independently reject an old or
modified client by build number; add authenticated build headers plus
server/RLS enforcement before treating minimum-version metadata as a security
boundary. Web/PWA updates continue through the atomic service-worker release
flow instead of the APK popup.

## Admin Notifications

The app, migrations, and Edge Functions implement this Firebase Cloud
Messaging delivery design, but live push is inactive until the client-owned
Firebase/APNs/web configuration and scheduled dispatcher are provided:

1. Each signed-in app registers its FCM token in `device_tokens`.
2. Customer order creation atomically queues in-app notifications and
   `notification_outbox` jobs for active admin/staff recipients.
3. Order status changes queue an update for the customer.
4. The scheduled `dispatch-notification-outbox` Edge Function sends Firebase
   HTTP v1 messages, records delivery attempts, and retries temporary failures.
5. The app opens the matching order or product when the user taps a push.

Android uses the single high-priority channel ID `animal_supply_orders` for both
Firebase background notifications and foreground local notifications. Web push
uses `app_service_worker.js` as the only root-scoped worker. While the web app
is open, foreground messages are shown as an Arabic in-app message with an
explicit **فتح** action; the web local-notification plugin is intentionally not
initialized because it would replace the offline/FCM worker.

No Firebase server credential should be placed in Flutter. Keep Firebase HTTP v1 credentials in Supabase Edge Function secrets only.

## Required Before Production

- Create the Firebase project.
- Add platform-specific Firebase configuration that is intentionally ignored by
  Git where platform tooling requires it, and pass the public Firebase App IDs
  through the ignored `mobile.public.json`. Web Firebase/VAPID values use the
  separate ignored `cloudflare.public.json`.
- Configure APNs in Firebase and enable Push Notifications in the client-owned
  Apple Developer account.
- Set `FIREBASE_SERVICE_ACCOUNT_JSON` and
  `NOTIFICATION_DISPATCH_SECRET` only as Supabase Edge Function secrets.
- Deploy and schedule `dispatch-notification-outbox`.

Until this is configured, the app still stores in-app notification rows and
clearly labels the push-delivery part as production-only.
