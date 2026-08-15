# Android Release Signing Handoff

The local production signing material is intentionally excluded from Git:

- `app/android/keystore/animal-supply-release.jks`
- `app/android/key.properties`

Release Gradle tasks fail closed when either file or any required signing
property is missing. A clean handoff machine must not silently produce an
unsigned artifact.

## Required Before Public Distribution

1. Copy both files to an encrypted password manager or encrypted offline drive.
2. Give the encrypted backup to the client or store it in a client-owned vault.
3. Record the alias `animal_supply_release`.
4. Test restoring the files on a clean machine and building a release APK.
5. Never email, commit, log, or paste the passwords into project documentation.

Every direct APK update must keep the same Android application ID and signing
certificate and must increase the Flutter build number/version code.

Losing this keystore can prevent installed direct-distribution builds from
updating normally.

## Current verified signed demo release

Built on August 11, 2026:

- Package/version: `ly.animalsupply.b2b` `1.0.4` (`versionCode 5`)
- SDK range: minimum 24, target 36
- APK size: `61,424,761` bytes
- AAB size: `48,192,356` bytes
- APK SHA-256:
  `cc2ff2954d9e082b440ef6472b07260ee2fea07412c25eed6648cc692ccc1b66`
- AAB SHA-256:
  `83f0154fbc402228ad0cf1e2e6d4b34b5a9500377bf8317cf5a814f4b1797bff`
- Release manifest:
  `app/build/release-manifests/android-1.0.4+5.json`
- Release manifest SHA-256:
  `ef06d09e759fe2f6f4f34beef8ed05e22d186b175075147f5954b97c5dd6837f`
- Signing certificate SHA-256:
  `C0:F6:8C:B3:06:7D:D4:FB:64:AA:50:D1:C8:00:2A:21:BC:EC:DA:DE:B4:DA:DD:A3:75:8E:43:5B:7D:11:0C:53`
- APK Signature Scheme v2, APK alignment, AAB JAR certificate/signature,
  APK/AAB ZIP integrity, Gradle bundle/signing pipelines,
  `validateSigningRelease`, Arabic installed label, release-manifest
  generation, and credential-shaped secret scans all passed.

These values apply only to the signed `1.0.4+5` demo artifacts. Rebuild with
the same long-term signing key and record new size, signature, and checksums
after adding approved production public configuration or changing source.
