# Client Handoff And Commercial Scope

Status date: August 13, 2026

## Commercial position

The agreed `7,000 LYD` is approximately `824 USD` at the supplied exchange
rate of `1 USD = 8.5 LYD`.

For a responsive Flutter web app, signed Android application, iOS project,
admin dashboard, secure backend, offline ordering, push-notification
infrastructure, deployment, testing, and handoff, this is a heavily discounted
MVP/pilot price. It should not be presented as an unlimited fixed price.

Use a written acceptance list and treat anything outside this document as a
paid change request.

At this price, absorbing production data entry, third-party fees, store-review
work, indefinite support, unlimited revisions, or client-requested scope
expansion would be commercially unsafe. Those items must be client-paid or
quoted separately.

## Current review status

The review build is available at
`https://animal-supply-b2b.alnaagi-ai.workers.dev`, Cloudflare version
`770b7a01-6575-49e9-8ca7-b77f393c8f5b`, app version `1.0.4+5`.

It is an intentionally `noindex` demo build. It does not have the client's
production Supabase/Firebase configuration, real catalog, permanent domain, or
native-store distribution and must not be described as a completed production
launch.

When the browser reports that the PWA is installable, the web build shows an
Arabic install dialog connected to the browser's native confirmation. Safari
on iPhone/iPad instead shows the correct Add to Home Screen steps.

## Included in the 7,000 LYD MVP

- Arabic-first, RTL customer experience for web, Android, and iOS project.
- Admin-created customer accounts; no public customer registration.
- Login, forced first-password change, suspension, archive, and restoration.
- Customer catalog, optional customer-wide product discounts, cart, checkout,
  and orders.
- Server-authoritative pricing, stock, minimum quantity, minimum order, and
  idempotent order creation.
- Admin order dashboard and controlled order status transitions.
- In-app notifications, targeted/broadcast campaign administration, and the
  Firebase/Supabase delivery integration code.
- One optional percentage discount for all products, managed from each
  customer's admin profile and resolved server-side.
- Product, inventory, product-image, banner, store-setting, and update
  metadata administration.
- Offline catalog/cart cache and safe queued-order retry.
- Cloudflare web/PWA deployment configuration.
- Android APK/AAB release preparation using the same long-term signing key.
- iOS Xcode project and release instructions.
- Source code, migrations, Edge Functions, tests, and technical handoff.

## Client-owned accounts and pass-through costs

These costs are not developer profit and should be paid directly by the client.
The baselines below were rechecked against the official vendor pages on
July 22, 2026:

| Item | Current baseline | LYD at 8.5 |
| --- | ---: | ---: |
| Apple Developer Program | 99 USD/year | about 842 LYD/year |
| Google Play Console, if used later | 25 USD one time | about 213 LYD |
| Supabase Free | 0 USD; 500 MB database quota before read-only behavior | 0 LYD |
| Supabase Pro | 25 USD/month; includes 8 GB database, 250 GB egress, and daily backups | about 213 LYD/month |
| Firebase Cloud Messaging | no-cost product | 0 LYD for FCM itself |
| Cloudflare Workers Static Assets | static-asset requests/storage are free; dynamic Worker usage follows plan limits | usually 0 LYD for this PWA pilot |
| Cloudflare Workers Paid, if needed | 5 USD/month minimum | about 43 LYD/month |
| Cloudflare R2 APK hosting | first 10 GB-month free; then standard storage starts at 0.015 USD/GB-month with free egress | usage dependent |
| Domain | depends on TLD and registrar | client choice |

Supabase Free projects can be paused, including for inactivity, so a
production client should either actively monitor the free project or budget
for Pro. Vendor pricing and regional taxes can still change; reconfirm at
purchase time:

- https://developer.apple.com/support/compare-memberships/
- https://support.google.com/googleplay/android-developer/answer/6112435
- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/billing-on-supabase
- https://firebase.google.com/pricing
- https://developers.cloudflare.com/workers/platform/pricing/

## Required client inputs before real production

- Final business name, logo, colors, legal text, delivery policy, and support
  WhatsApp number.
- Approved product catalog, real prices, minimum quantities, stock, images,
  and image licensing.
- A client-owned domain and DNS access.
- A client-owned Supabase project and billing decision.
- A client-owned Firebase project, Android/iOS/web app registrations, APNs
  setup, and VAPID key.
- Apple Developer/App Store Connect access for TestFlight, Ad Hoc, or App Store
  distribution.
- A permanent controlled host for signed Android APK files.
- Named admin/staff users and a customer onboarding list.
- Acceptance testing and written approval.

## Distribution decision

### Web and PWA

The Cloudflare URL can be sent through WhatsApp or QR immediately. On iPhone
and Android, users can add the PWA to the home screen without store review.

### Android

A signed APK can be shared by HTTPS link or QR. Android still requires the
user to approve installation from that source. Every update must use the same
signing key and a higher build number.

### iPhone and iPad

An arbitrary IPA link is not the iOS equivalent of an APK link. Use:

- TestFlight for a normal client pilot;
- Ad Hoc only for devices whose identifiers are registered in the client's
  Apple Developer account and included in the provisioning profile;
- the PWA when immediate link-based access is required.

A signed native iOS release must be archived on macOS with Xcode and the
client's Apple team. TestFlight/App Store review timing is controlled by Apple,
not by this development quote.

## Maintenance and change requests

Suggested commercial boundary after acceptance:

- Warranty period: 14 days for defects in the accepted scope.
- Basic maintenance: `600-1,000 LYD/month` for monitoring, backups,
  dependency/security checks, and a small capped support allowance.
- Active operations plan: `1,200-2,500 LYD/month` when it includes catalog
  work, campaigns, releases, priority support, or recurring changes.
- Major features: quoted separately before implementation.
- Emergency/out-of-scope work: agreed hourly or fixed estimate before work.

Keep hosting and third-party invoices separate from maintenance.

## Additional paid features

- Online/card/mobile-wallet payments and financial reconciliation.
- Full credit ledger, statements, payments, aging, and automatic credit holds.
- Multi-warehouse inventory, purchasing, supplier management, and stock
  transfers.
- Delivery driver app, dispatch, maps, and live tracking.
- WhatsApp Business API automation and approved message templates.
- AI catalog assistant, support chatbot, product recommendations, or demand
  forecasting.
- Barcode scanning, batch/expiry tracking, and label printing.
- Loyalty, coupons, referral codes, sales representatives, and commissions.
- Accounting/ERP integration.
- Advanced analytics and scheduled business reports.
- Multi-language, multi-currency, multi-company, or white-label variants.
- App Store/Google Play submission and review-response work.

## Acceptance boundary

Delivery is accepted when the agreed workflows pass on the approved staging
environment:

1. Admin creates a customer and securely sends the one-time invitation.
2. Customer signs in and changes the temporary password.
3. Customer sees authoritative pricing and stock.
4. Customer completes or safely queues an order.
5. Admin receives and processes the order through valid statuses.
6. Customer sees the order update and notification history.
7. Admin can manage catalog, customer-wide discounts, banners, campaigns, and
   update metadata.
8. Web and Android release artifacts pass the handoff checklist.

Production launch remains blocked until the client supplies the accounts,
catalog, domain, Firebase/APNs configuration, and final acceptance listed
above. Cloudflare R2 is also currently disabled on the existing account, so it
must be enabled or replaced with another controlled HTTPS APK host.

The exact technical launch sequence is maintained in
`CLOUDFLARE_DEPLOYMENT.md`; Android and iOS limitations are maintained in
`DEPLOYMENT_ANDROID_APK.md` and `DEPLOYMENT_IOS.md`.
