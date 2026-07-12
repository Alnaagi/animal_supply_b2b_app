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
flutter build appbundle --release
```

The signed APK is written to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

The Google Play bundle is written to:

```text
build/app/outputs/bundle/release/app-release.aab
```

## Signing

Release signing is configured locally through ignored files:

- `app/android/keystore/animal-supply-release.jks`
- `app/android/key.properties`

Follow `ANDROID_SIGNING_HANDOFF.md` before handing the project to the client.
Never commit, send by WhatsApp, or add the keystore password to a build command.

## Download Link Settings

App settings include:

- `app_download_link`
- `apk_link`
- future `play_store_link`
- future `app_store_link`

Admin can later update these values in `app_settings` so WhatsApp invite messages point to the newest APK.

For every direct-distribution update:

1. Keep application ID `ly.animalsupply.b2b`.
2. Keep the same signing certificate.
3. Increase `version` in `app/pubspec.yaml`.
4. Publish the file only through an HTTPS link controlled by the client.
5. Add the matching `app_versions` row with release notes and SHA-256.

## iOS Note

See `DEPLOYMENT_IOS.md`. An iOS `.ipa` cannot use the Android APK download
flow.
