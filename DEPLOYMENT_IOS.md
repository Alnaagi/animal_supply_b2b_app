# iOS Distribution And Updates

## Decision

iOS does not use the Android APK download flow. Do not upload an `.ipa` to
Google Drive and expect it to install for arbitrary customers.

For a client pilot, choose one client-owned Apple distribution method:

1. **TestFlight** for the normal beta path and feedback collection. External
   testing can require Apple's beta review and Apple controls processing time.
2. **Ad Hoc** only for a known set of device identifiers registered in the
   client's Apple Developer account and included in the provisioning profile.
3. **A PWA/web app** for users who must open the product from a WhatsApp or QR
   link without an iOS install step.

Do not use Enterprise distribution for unrelated customers; that channel is
for an eligible organization's internal use. An update popup can open the
chosen TestFlight, App Store, Ad Hoc, or web destination, but it cannot bypass
iOS signing, provisioning, review, or user approval.

Keep the Apple Developer account, App Store Connect access, signing
certificates, and APNs credentials owned by the client—not a personal
developer account.

## Project Configuration Already Present

- Bundle ID: `ly.animalsupply.b2b`
- Custom invite scheme: `animalsupplyb2b://invite`
- Push entitlement switches to `development` for Debug and `production` for
  Release/Profile builds.
- Remote-notification background mode is declared.

## Required Client Inputs

1. Client Apple Developer team and App ID for `ly.animalsupply.b2b`.
2. Push Notifications enabled for that App ID.
3. `GoogleService-Info.plist` from the client Firebase project; keep it
   uncommitted.
4. APNs key/certificate configured in Firebase.
5. A production HTTPS domain if WhatsApp invite links should open the installed
   app automatically. Configure Apple Associated Domains and host
   `apple-app-site-association` on that domain.

Until a real domain is configured, send users a download/onboarding web link
plus the custom-scheme invite as a convenience after the app is installed.

## Build On macOS

The current Fedora development host cannot produce or sign the final iOS
archive. A Mac with a compatible Xcode version is required.
The Flutter source version is currently `1.0.4+5`; generated iOS build
settings on Fedora are not release evidence and must be regenerated on the Mac.

```bash
cd /path/to/animal_supply_b2b_app
cp mobile.public.example.json mobile.public.json

cd app
flutter clean
flutter pub get
FLUTTER_BIN=flutter \
  node tool/build_mobile_release.mjs ios \
  --dart-define-from-file=../mobile.public.json
```

Build and archive on a Mac with Xcode, the client signing team selected, and
the correct distribution method. Before archiving, verify Xcode resolves
`FLUTTER_BUILD_NAME=1.0.4` and `FLUTTER_BUILD_NUMBER=5` from `pubspec.yaml`.
Increment the Flutter build number before every new uploaded or Ad Hoc build.

The wrapper validates the public build configuration, scans the resulting
artifact for secret-shaped content, and writes a checksummed release manifest.

The ignored `mobile.public.json` contains public client identifiers only.
Supabase service-role credentials, Firebase service-account JSON, APNs private
keys, certificates, and signing passwords must never be compiled into the app.

## Native release checklist

1. Confirm the bundle ID and version/build number.
2. Select the client-owned Apple team and intended TestFlight/App Store or
   Ad Hoc provisioning profile.
3. Add the uncommitted Firebase configuration, APNs capability, and required
   privacy/permission descriptions.
4. Configure the final HTTPS domain, Associated Domains entitlement, and
   `apple-app-site-association` file before relying on universal invite links.
5. Run Flutter tests, build/archive in Xcode, and test login, forced password
   change, ordering, order updates, notification taps, offline recovery, and
   update links on physical iPhone/iPad hardware.
6. Upload through Xcode/App Store Connect for TestFlight, or export an Ad Hoc
   IPA whose provisioning profile contains every allowed device.
7. Keep signing certificates, private keys, APNs credentials, and provisioning
   profiles outside Git and hand them over through a secure client-controlled
   process.

## Updates

- TestFlight updates are managed through Apple’s beta channel.
- Ad Hoc updates require a newly signed IPA distributed to the registered
  devices.
- The in-app update metadata can show release notes and open a client-owned
  destination, but iOS still controls installation and trust.
