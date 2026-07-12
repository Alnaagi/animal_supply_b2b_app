# iOS Distribution And Updates

## Decision

iOS does not use the Android APK download flow. Do not upload an `.ipa` to
Google Drive and expect it to install for arbitrary customers.

For a client pilot, choose one client-owned Apple distribution method:

1. **TestFlight** for the normal beta path and feedback collection.
2. **Ad Hoc** only for a known, registered set of customer devices.
3. **A PWA/web app** for users who must open the product from a WhatsApp or QR
   link without an iOS install step.

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

```bash
cd app
flutter pub get
flutter build ipa --release
```

Build and archive on a Mac with Xcode, the client signing team selected, and
the correct distribution method. Increment the Flutter build number before
every new uploaded or Ad Hoc build.

## Updates

- TestFlight updates are managed through Apple’s beta channel.
- Ad Hoc updates require a newly signed IPA distributed to the registered
  devices.
- The in-app update metadata can show release notes and open a client-owned
  destination, but iOS still controls installation and trust.
