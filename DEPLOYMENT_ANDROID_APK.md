# Android APK Deployment

## Debug APK

```bash
cd app
flutter build apk --debug
```

Output is usually:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Release APK

```bash
flutter build apk --release
```

## Signing Placeholder

Create a keystore before production release and configure `android/key.properties` and Gradle signing. Do not commit real keystore passwords.

## Download Link Settings

App settings include:

- `app_download_link`
- `apk_link`
- future `play_store_link`
- future `app_store_link`

Admin can later update these values in `app_settings` so WhatsApp invite messages point to the newest APK.

## iOS Note

iOS sideloading is not equivalent to Android APK. Outside App Store requires TestFlight, enterprise signing, Apple Developer account, or a PWA alternative.
