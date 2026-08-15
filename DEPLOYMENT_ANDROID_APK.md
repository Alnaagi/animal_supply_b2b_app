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

Create the ignored public mobile build file and replace every placeholder:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app
cp mobile.public.example.json mobile.public.json

cd app
FLUTTER_BIN=/home/alnaagi/development/flutter/bin/flutter \
  node tool/build_mobile_release.mjs android \
  --dart-define-from-file=../mobile.public.json
```

`mobile.public.json` may contain only browser/mobile public identifiers. Never
put a Supabase service-role key, Firebase service account, signing password,
private key, database URL/password, or dispatcher secret in it. Production
startup fails closed when the Supabase public key, client origin, customer
login domain, or platform Firebase App ID is missing or unsafe.

The wrapper builds both APK and AAB, rejects secret-shaped artifact content,
and writes a checksummed public release manifest under
`app/build/release-manifests/`. Do not replace it with an unguarded release
command in the delivery procedure.

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
Release tasks deliberately fail if the ignored signing configuration or
keystore is missing, so an unsigned file cannot be mistaken for a deliverable.

After every final source change, rebuild both artifacts and verify the current
APK rather than reusing an older checksum:

```bash
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
sha256sum \
  build/app/outputs/flutter-apk/app-release.apk \
  build/app/outputs/bundle/release/app-release.aab
```

Record the generated size, version, signer certificate digest, and SHA-256
values in the release handoff. No checksum is authoritative until it is
generated from the exact artifact being delivered.

The current verified signed August 11, 2026 demo build is recorded in
`ANDROID_SIGNING_HANDOFF.md`. It is version `1.0.4+5`, signed with the same
long-term key, and installable for controlled testing. Rebuild it again after
the real Supabase/Firebase public configuration is approved or after any source
change.

## Download Link Settings

App settings include:

- `download_link`: the stable HTTPS onboarding/download page used in invites.
- `apk_link`: the direct HTTPS Android artifact link.
- future `play_store_link`
- future `app_store_link`

Admin can update these values in `app_settings`. WhatsApp invites should use
the stable `download_link`; Android update metadata uses the exact signed
artifact URL in `app_versions.apk_url`.

For every direct-distribution update:

1. Keep application ID `ly.animalsupply.b2b`.
2. Keep the same signing certificate.
3. Increase `version` in `app/pubspec.yaml`.
4. Publish the file only through an HTTPS link controlled by the client.
5. Add the matching `app_versions` row with release notes, SHA-256, and
   positive artifact size.
6. Install over the previous signed release on a physical test device and
   verify that Android accepts it as an update.

## iOS Note

See `DEPLOYMENT_IOS.md`. An iOS `.ipa` cannot use the Android APK download
flow.
