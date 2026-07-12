# Security

## No Public Registration

There is no customer sign-up screen. Accounts are created by admin/staff only.

## No Password In Links

Invite links must never contain real passwords. The WhatsApp message may show a temporary password as text for MVP. The link contains only a one-time token and optional client code.

Example safe link:

```text
animalsupplyb2b://invite?token=inv_xxx&client=tripoli-pets
```

## Invite Token Logic

- Token is random, one-time, and expiring.
- Production should store only token hash.
- On open, app can pre-fill username/client code.
- User manually enters temporary password.
- `must_change_password` should force password change after first login.

## RLS

RLS is the main data boundary. The Flutter app uses anon key only. Customers cannot update order status or read other customers.

## Admin Permissions

Admin can manage all. Staff permissions can be tightened later with per-action flags.

## APK Distribution Risks

Direct APK distribution skips store review and automatic update trust. Use signing, checksums, HTTPS download links, and a clear update process. iOS outside the App Store requires TestFlight, enterprise signing, Apple Developer account, or PWA alternative.
