# Mobile APK Testing, Updates, And Notifications

## Distribution Choice

This project targets direct Android APK distribution for testing and early production. The app is not assumed to be on Google Play.

Recommended setup:

1. Build a signed release APK.
2. Host it at the configured `APK_LINK`.
3. Add the newest version row to Supabase `app_versions`.
4. The app opens the APK link when an update is available.

Android will still ask the user to approve installing apps from that source. A normal APK app cannot silently replace itself unless the devices are managed through device-owner/MDM style controls.

## Build Commands

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app
flutter build apk --debug
flutter build apk --release
```

Release updates require:

- Same Android package name.
- Same signing key.
- Higher `versionCode`.

## Update Strategy

Use a hybrid strategy:

- Shorebird OTA: quick Flutter/Dart/UI fixes after Shorebird is configured.
- Signed APK update: native plugins, permissions, Firebase config, app icon, Android manifest, package/signing, or anything Shorebird cannot patch.
- Supabase `app_versions`: controls latest APK URL, release notes, optional/required update flags.

## Admin Notifications

The planned production path is Firebase Cloud Messaging:

1. Each signed-in app registers its FCM token in `device_tokens`.
2. Customer order creation atomically queues in-app notifications and
   `notification_outbox` jobs for active admin/staff recipients.
3. Order status changes queue an update for the customer.
4. The scheduled `dispatch-notification-outbox` Edge Function sends Firebase
   HTTP v1 messages, records delivery attempts, and retries temporary failures.
5. The app opens the matching order or product when the user taps a push.

No Firebase server credential should be placed in Flutter. Keep Firebase HTTP v1 credentials in Supabase Edge Function secrets only.

## Required Before Production

- Create the Firebase project.
- Add platform-specific Firebase configuration that is intentionally ignored by
  Git: Android `google-services.json`, iOS `GoogleService-Info.plist`, and web
  Firebase/VAPID values passed at build time.
- Configure APNs in Firebase and enable Push Notifications in the client-owned
  Apple Developer account.
- Set `FIREBASE_SERVICE_ACCOUNT_JSON` and
  `NOTIFICATION_DISPATCH_SECRET` only as Supabase Edge Function secrets.
- Deploy and schedule `dispatch-notification-outbox`.

Until this is configured, the app still stores in-app notification rows and
clearly labels the push-delivery part as production-only.
