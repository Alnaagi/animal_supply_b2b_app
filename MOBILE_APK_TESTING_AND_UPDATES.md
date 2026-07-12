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

1. Admin/staff app registers an FCM token.
2. Token is stored in `admin_device_tokens`.
3. Customer submits an order.
4. Supabase Edge Function `send-admin-notification` stores a notification row and is the server-side place to send FCM.
5. Admin phone receives a push notification and opens the order detail.

No Firebase server credential should be placed in Flutter. Keep Firebase HTTP v1 credentials in Supabase Edge Function secrets only.

## Current MVP State

- Admin notification table/function scaffolding exists.
- App version/update metadata exists.
- The app can show/open APK update links.
- Full Firebase client setup still needs a Firebase project and Android `google-services.json`.
