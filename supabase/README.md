# Supabase production setup

This directory is migration-first. `schema.sql` is a legacy reference only,
and `rls.sql` intentionally raises an error so an old deployment command cannot
replace the final migration-owned policies.

## Database

For a new or existing linked Supabase project:

```bash
supabase db push
```

For a fresh project, the migration chain validates cleanly because there is no
legacy data. For an existing project already migrated through `024`, run
`legacy_constraints_preflight.sql` before migration `027`. If a normal
`supabase db push` stops on `027`, the earlier migrations remain the required
baseline: run the legacy diagnostics, repair the reported rows, and retry the
push. Do not weaken or skip the validating constraints. The broader
`production_preflight.sql` is post-migration-031 only because it checks fields
and security routines introduced later in the chain.

The migration chain:

1. Creates the initial schema for a new project without duplicating existing
   legacy tables.
2. Adds secure order snapshots, idempotency, stock reservations, status
   history, invites, device tokens, notification outbox/delivery logs, update
   metadata, constraints, and transactional server functions.
3. Replaces prototype policies with active-account and owner-scoped RLS.
4. Returns reservation-aware availability through a scoped aggregate helper;
   customers never receive direct reservation-row access.
5. Binds each order idempotency UUID to a canonical request fingerprint and
   enforces exact reservation/order-item identity.
6. Validates every legacy constraint that was introduced as `NOT VALID`.
7. Gates first-password completion through a redeemed one-time invite,
   hardens customer/contact RLS, and deactivates device tokens when an account
   is locked.
8. Adds bounded admin dashboard/report aggregate RPCs without granting client
   access to service-role operations.
9. Adds stable-snapshot, bounded catalog pages and filter facets using
   `SECURITY INVOKER`, existing RLS, effective customer-wide discounts, and
   reservation-aware availability.
10. Migration `202607220031_simplified_product_controls.sql` adds the
    simplified wholesale/retail-reference fields, optional box metadata,
    tracked/untracked inventory behavior, customer out-of-stock visibility,
    immutable order-line snapshots, and matching catalog/order safeguards.
11. Migration `202608020032_banner_images_storage.sql` keeps banner media
    writes admin-only, requires exact
    `product-images/banners/{auth.uid()}/{file}` ownership, and removes the
    legacy staff-write policies.
12. Migration `202608160042_shop_logo_storage.sql` stores the shop logo in
    `product-images/logos/{auth.uid()}/{file}`, keeps writes admin-only, and
    lets `anon` read `shop_name` and `shop_logo_url` for login/download chrome.
13. Migration `202608160046_category_icons.sql` stores a preset `icon_key`
    and/or public `icon_url` on `categories`, requires one of them, and allows
    staff/admin uploads under `product-images/category-icons/{auth.uid()}/{file}`.

On July 23, 2026, the complete 18-migration chain through
`202607220031_simplified_product_controls.sql` and `seed.sql` was applied in an
isolated local Supabase/PostgreSQL runtime. Database lint reported no schema
errors, `production_preflight.sql` returned zero blockers, the expected
constraints and security-function grants matched, and the migration-031
product/inventory plus activation/delivery security suites passed. Earlier
catalog, reservation, idempotency, and aggregate suites remain part of the
required staging role matrix. Repeat the complete preflight and role matrix
against the client staging project; local validation does not prove the
eventual hosted configuration.

Migration `202608020032_banner_images_storage.sql` was added after that local
database run. Docker/PostgreSQL was unavailable on August 11, 2026, so apply
the full 19-migration chain through `032` and rerun
`production_preflight.sql` against the client staging project before
activation.

Before production, confirm in the hosted Auth settings that public email,
phone, and anonymous sign-up are disabled. Customers are created only by the
privileged admin Edge Function.

## Simplified product pricing and inventory controls

Apply `202607220031_simplified_product_controls.sql` before deploying a Flutter
build that reads or writes the simplified product fields.

The Arabic admin form maps to the database as follows:

- `اسم المنتج` -> `products.name`;
- `اسم الشركة` -> `products.brand`;
- `سعر الجملة` -> `products.base_price`, subject to the customer's optional
  server-resolved all-products discount;
- `سعر بيع الوحدة المقترح` -> `products.retail_unit_price`;
- `الحد الأدنى لطلب الجملة` -> `products.min_order_quantity`;
- optional `الكمية في العلبة` -> `products.units_per_box`;
- `تتبع المخزون` and its quantity -> `products.stock_tracking_enabled` and
  `products.stock_quantity`;
- customer visibility -> `products.active`;
- hide instead of show unavailable -> `products.hide_when_out_of_stock`.

This application sells wholesale only. `base_price` or the server-resolved
effective price is the authoritative price for each sellable order unit.
`retail_unit_price` is only a suggested downstream single-unit resale price for
the customer and must never affect `order_items.unit_price`, line totals,
subtotals, fees, reservations, or inventory arithmetic. `units_per_box` is
optional display metadata and also does not multiply price or order quantity.
The seller must define the sellable unit consistently, typically a box or case.

### Customer-wide discount transition

The active customer-pricing contract is one optional percentage stored as
`business_customers.discount_percent`. An admin manages it from the customer
profile, and the server applies it uniformly to every product's `base_price`
when returning customer catalog prices and when creating an order.

The similarly named `products.discount_percent` field remains legacy
product-promotion metadata. It may be displayed with product campaign data, but
it is not the customer's negotiated discount and does not independently define
the authoritative order price.

The legacy `price_groups`, `product_prices`, and `customer_special_prices`
tables remain present but dormant during the transition. Their existing rows
are retained for compatibility and audit safety; active catalog and order
pricing must not consult them. Do not drop or clear those tables without a
separate reviewed migration, backup, and explicit approval.

Order creation continues to snapshot the resolved `unit_price` into
`order_items`. Updating a customer's discount changes future prices only and
must never rewrite existing order-item or order-total history.

At order creation, migration 031 snapshots `units_per_box`,
`retail_unit_price`, and `stock_tracking_enabled` into the order item so
historical screens retain the product context. The server still resolves the
wholesale price, validates the bulk MOQ, and stores that resolved value in the
order item.

Inventory behavior:

- tracked products expose reservation-adjusted availability and may be ordered
  only when the requested quantity and remaining availability satisfy the MOQ;
- a tracked product below its MOQ is removed from customer reads when
  `hide_when_out_of_stock=true`, or remains visible and non-orderable when the
  flag is false;
- untracked products expose no finite `available_quantity`, are not capped by
  stock, do not deduct stock or create inventory movements when delivered, and
  are excluded from low-stock reporting;
- untracked order lines still keep exactly one reservation row for
  audit/relational integrity, but that reservation is not counted as tracked
  stock;
- disabling tracking is rejected with
  `STOCK_TRACKING_HAS_ACTIVE_RESERVATIONS` while active tracked reservations
  exist for the product.

The customer product RLS policy and the `SECURITY INVOKER`
`catalog_products`/`catalog_products_page` functions enforce active,
non-archived visibility and the hide-when-unavailable choice. Staff/admin
catalog access remains role-checked. Migration 031 does not grant authenticated
clients access to service-role order/status functions, reservation tables, or
privileged customer-account discount mutations.

### Migration 031 verification

Run the migration and these checks in an isolated local or staging database
before the hosted production push:

1. Run `production_preflight.sql`. Its first violation result must contain zero
   rows.
2. Confirm every expected product/order-item constraint reports
   `exists=true` and `validated=true`, and that the security-function
   role/grant matrix matches the expected values.
3. Run the rollback-only
   `tests/product_inventory_behavior.sql` with active, unlocked customer and
   admin profile UUIDs:

   ```bash
   psql "$DATABASE_URL" \
     -v customer_profile_id="$CUSTOMER_PROFILE_ID" \
     -v admin_profile_id="$ADMIN_PROFILE_ID" \
     -f supabase/tests/product_inventory_behavior.sql
   ```

4. The suite must verify hidden-vs-visible unavailable products, nullable
   availability for untracked products, wholesale totals unaffected by the
   retail reference, snapshot preservation, tracked-reservation toggle
   protection, and no stock deduction/inventory movement for untracked
   delivery.
5. Re-run the existing catalog, reservation, idempotency, RLS role-matrix,
   database-lint, and application order-flow tests. Migration 031 is not
   production-ready if any prior security/concurrency suite regresses.

## Product image storage

Migration `202607210023_product_images_storage.sql` creates the public
`product-images` bucket for product catalog delivery. Apply it with the normal
`supabase db push` migration flow before enabling upload in the admin app.

Security and operational rules:

- object reads use public HTTPS bucket URLs so catalog images work on web,
  Android, and iOS;
- uploads accept only JPEG, PNG, and WebP and are capped at 5 MiB by both the
  Flutter repository and the bucket;
- Flutter uploads with the signed-in anon client; no service-role credential
  belongs in the app;
- active staff/admin users may insert only under randomized
  `products/<profile-id>/...` paths owned by their authenticated profile;
- the admin product form keeps a manually entered HTTPS URL as a fallback;
- demo or unconfigured builds never fake an upload and explain that the
  production Supabase backend is required.

The app does not automatically delete an older image when a product is edited.
Periodically audit unreferenced objects, or add a guarded cleanup job after the
client approves retention rules.

## Edge Function configuration

Configure these values as Edge Function secrets. Never place them in Flutter,
web assets, APK/IPA files, client logs, QR codes, or committed configuration.

- `ALLOWED_ORIGINS`: comma-separated exact production web origins. Local web
  origins must also be listed explicitly during development; wildcard origins
  are not accepted. `APP_PUBLIC_ORIGIN` is also accepted so the live shop host
  can call campaign and device-token functions.
- `INVITE_BASE_URL`: the HTTPS universal/app-link invite URL.
- `CUSTOMER_LOGIN_DOMAIN`: a real client-controlled DNS domain used to map
  customer usernames to internal Auth email identifiers. It must exactly match
  the public `CUSTOMER_LOGIN_DOMAIN` Flutter build value.
- `RATE_LIMIT_SALT`: a random server-only rate-limit hashing salt containing at
  least 32 characters. Hosted functions fail closed when it is absent or too
  short; only a local Supabase URL receives a development fallback.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: Firebase service-account JSON used only by
  the notification dispatcher.
- `NOTIFICATION_DISPATCH_SECRET`: a separate random secret used by the
  scheduled outbox dispatcher.
- `APP_DOWNLOAD_LINK`: optional server-side fallback download page.

- `DATABASE_DISK_QUOTA_BYTES`: optional Postgres disk quota in bytes used by
  `admin-database-usage`. When unset, the function uses 500 MiB (the documented
  Free-plan database quota).

`admin-reset-application-data` is an admin-only Edge Function. It requires a
user JWT, an active `profiles.role = admin` row, rate limiting, and the exact
body phrase `RESET`. It truncates application tables (catalog, orders,
customers, banners, inventory, invites, notifications, device tokens, price
groups) via `admin_reset_application_data`, deletes customer Auth users, and
empties the `product-images` bucket. It does not delete the calling admin Auth
user, other admin/staff profiles, `app_settings`, `app_versions`, `audit_logs`,
or `edge_rate_limits`. There is no public or anonymous wipe. Flutter never
receives the service role.

Privileged database credentials must remain in the managed Edge runtime only.

Deploy the functions:

```bash
supabase functions deploy admin-create-customer
supabase functions deploy admin-update-customer
supabase functions deploy admin-reset-customer-password
supabase functions deploy admin-database-usage
supabase functions deploy admin-reset-application-data
supabase functions deploy admin-update-order-pricing
supabase functions deploy generate-invite-token
supabase functions deploy redeem-invite
supabase functions deploy complete-password-change
supabase functions deploy place-order
supabase functions deploy transition-order-status
supabase functions deploy register-device-token
supabase functions deploy unregister-device-token
supabase functions deploy send-notification-campaign
supabase functions deploy dispatch-notification-outbox
supabase functions deploy send-admin-notification
```

`send-admin-notification` is compatibility-only. New clients must use
`place-order`, which commits the order, reservations, audit record, admin
notifications, and outbox rows atomically.

## Push dispatch

Create a Supabase scheduled invocation for
`dispatch-notification-outbox` (for example, once per minute). Send:

- a valid gateway authorization token suitable for scheduled function calls;
- the configured dispatch secret in `x-dispatch-secret`;
- JSON body such as `{ "limit": 50 }`.

The dispatcher:

- claims jobs with `FOR UPDATE SKIP LOCKED`;
- sends through Firebase HTTP v1;
- records per-device delivery results;
- deactivates stale tokens;
- retries temporary failures with exponential backoff;
- avoids resending to devices already marked delivered;
- stops automatic retries when Firebase accepted a message but its database
  receipt could not be saved, because retrying that uncertain delivery could
  send a duplicate;
- marks permanently failing jobs dead after the retry limit.

Firebase still requires platform configuration outside Supabase: Android
Firebase config, Apple APNs credentials, iOS entitlements, and a web push
service worker/VAPID setup.

Device-token registration is limited to 60 requests per authenticated profile
per hour. The registration transaction keeps at most eight active tokens per
profile and deactivates the oldest excess entries. Authenticated clients have
no direct table privileges on `device_tokens`; registration and removal must
use the corresponding Edge Functions, and dispatch remains service-role-only.

## Main API contracts

All responses use:

```json
{
  "ok": true,
  "data": {}
}
```

Errors use:

```json
{
  "ok": false,
  "error": {
    "code": "STABLE_ERROR_CODE",
    "message": "Safe message",
    "details": {}
  }
}
```

### `place-order`

```json
{
  "client_request_id": "UUID",
  "delivery_address": "Optional address",
  "customer_note": "Optional note",
  "delivery_note": "Optional note",
  "items": [
    {
      "product_id": "UUID",
      "quantity": 2
    }
  ]
}
```

The server resolves the customer's all-products discount against the base
wholesale price, validates the active account, bulk MOQ, tracked stock
reservations, and minimum order amount, then returns the authoritative order
with immutable snapshots. The reference-only retail unit price, product-level
promotion metadata, and optional units-per-box metadata never change the
charged amount. Reusing a
`client_request_id` is accepted only when the normalized items, resolved
delivery address, and notes match the original request. A changed payload
returns `IDEMPOTENCY_CONFLICT`.

### `generate-invite-token`

This endpoint creates activation invites only. Send no `purpose`, or send
`"purpose": "activation"`. Password resets must use
`admin-reset-customer-password`, which atomically creates the reset invite,
updates the Auth password, and sets the forced-password-change flag.

### `transition-order-status`

```json
{
  "order_id": "UUID",
  "status": "confirmed",
  "note": "Optional admin note"
}
```

Allowed transitions:

- `pending` to `confirmed` or `cancelled`
- `confirmed` to `preparing` or `cancelled`
- `preparing` to `ready` or `cancelled`
- `ready` to `delivered` or `cancelled`
- `delivered` and `cancelled` are terminal

### `admin-update-customer`

Existing customer edits are sent to this admin/staff-only Edge Function.
Authenticated clients have select-only access to `business_customers`; the
function validates the linked target profile is a customer, applies the update
through a service-role-only database transaction, and writes an audit record.

```json
{
  "customer_id": "UUID",
  "business_name": "اسم النشاط",
  "contact_person": "اسم المسؤول",
  "phone": "+218910000001",
  "city": "طرابلس",
  "area": "حي الأندلس",
  "address": "العنوان",
  "discount_percent": 12.5,
  "account_status": "active",
  "credit_limit": 2500,
  "outstanding_balance": 420
}
```

### `send-notification-campaign`

```json
{
  "idempotency_key": "11111111-1111-4111-8111-111111111111",
  "title": "عنوان عربي",
  "body": "نص الإشعار",
  "type": "promotion",
  "payload": {
    "screen": "catalog"
  },
  "audience": {
    "type": "role",
    "role": "customer"
  }
}
```

Audience types are `all`, `role`, `roles`, `profile_ids`, `customer_ids`, and
`city`. Use `roles` with `{"roles":["admin","staff"]}` when an operational
campaign must reach both active administrators and staff.

The client creates one UUID `idempotency_key` before sending and reuses it
after a timeout or network failure. Repeating the same campaign returns the
original recipient count without creating duplicate notifications. Reusing
the UUID with different content returns `CAMPAIGN_ID_CONFLICT`.

Campaigns fan out to one notification row per active profile so read state is
never shared between users. The admin app reads
`notification_campaign_summaries` for recipient, pending, retrying, dead, and
provider-accepted device-message counts. Only active administrators can call
that summary RPC.

When `payload.product_id` is present, the Edge Function accepts only a valid
UUID for an active, non-archived product. This prevents a campaign from
publishing a broken product destination.

## Final security and data checks

The final migration chain also:

- blocks suspended, archived, inactive, and forced-password-change actors in
  shared RLS helpers;
- removes authenticated direct writes to profiles, business customers, and
  legacy device-token paths;
- prevents an order from advancing through fulfillment unless every order
  item has a matching reservation;
- prevents tracked product stock from being saved below active tracked
  reservations and blocks unsafe tracking disablement;
- returns reservation-adjusted tracked availability without granting customer
  access to reservation rows, while untracked products expose no finite stock
  cap and do not deduct stock;
- enforces customer hide-vs-show-unavailable behavior in product RLS and
  `SECURITY INVOKER` catalog functions;
- preserves the reference retail price, optional box quantity, and tracking
  mode as immutable order-item snapshots without allowing them to affect
  authoritative wholesale totals;
- rejects reuse of an order idempotency UUID with a changed request payload;
- enforces the reservation's order, item, product, and quantity as one
  relational identity;
- validates every legacy row against the additive hardening constraints;
- keeps writes to the dormant price-group and customer-special-price tables
  restricted during the compatibility transition, while active customer-wide
  discount changes use the audited customer-update boundary;
- limits product-image maintenance to active staff/admin object ownership,
  while product media remains intentionally public catalog content.
- requires a redeemed invite before completing a forced password change and
  revokes stale device tokens for locked accounts;
- keeps dashboard/report aggregates and catalog paging role-checked, bounded,
  reservation-aware, and behind authenticated execution grants.

Before applying migration `027` to an existing project, run
`supabase/legacy_constraints_preflight.sql` as described above. After migration
`031`, run the current read-only queries in
`supabase/production_preflight.sql`. Resolve every
constraint violation, missing active-product retail reference, unsupported MOQ
or box quantity, reservation identity mismatch, unsafe tracked/untracked
transition, missing reservation, or tracked-stock deficit. Inspect all
existing `product-images` objects before the bucket becomes public, and review
any dashboard-created permissive policy that could widen access.

Credit limit and outstanding balance are currently audited reference fields.
They do not form an accounting ledger and do not automatically approve or
reject orders. Add a ledger/credit-policy phase before promising automated
credit control to the client.

## Maintenance mode

The admin setting `maintenance_mode=true` blocks new `place-order` requests at
the Edge Function boundary. Existing orders remain visible and staff/admin
operations continue to work. This setting takes effect only after the
`place-order` function is deployed.
