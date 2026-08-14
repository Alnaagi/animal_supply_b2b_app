# Animal Supply B2B Flutter App

Arabic-first, RTL Flutter client for customer, staff, and admin roles. Customer
accounts are created by authorized staff; there is no public sign-up flow.

Run local validation from this directory:

```bash
/home/alnaagi/development/flutter/bin/flutter pub get
/home/alnaagi/development/flutter/bin/flutter analyze
/home/alnaagi/development/flutter/bin/flutter test
```

Run without Supabase values for the clearly labelled demo/offline-friendly
mode. Production builds require the public configuration described in the
repository root `README.md` and `CLOUDFLARE_DEPLOYMENT.md`; never provide
service-role, Firebase service-account, signing, or database secrets through
Flutter build defines.

Use `tool/build_web_release.mjs` for web releases so the generated offline
shell manifest matches the exact build. Android and iOS distribution
instructions are maintained in the repository root deployment documents. Use
`tool/build_mobile_release.mjs` for final Android/iOS artifacts so public
configuration is validated, secret-shaped artifact content is rejected, and
a checksummed release manifest is generated.
