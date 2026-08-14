# Roadmap

## Phase 1 MVP

- Arabic Flutter mobile app.
- Demo mode repositories.
- Supabase schema, RLS, seed, and Edge Function skeletons.
- Admin-created customer flow.
- WhatsApp invite generation.
- Catalog, cart, order submission, profile, admin dashboard.

## Phase 2 Offline Resilience

- Completed: persisted catalog/cart cache with account isolation.
- Completed: offline order outbox with timed exponential retry and status
  indicators.
- Completed: connectivity recovery that submits product IDs and quantities
  without trusting cached prices.
- Production invariant: the Edge Function revalidates customer status, current
  prices, MOQ, inventory, reservations, and idempotency.
- Optional future expansion: a richer local database and conflict UI if the
  client later requires large offline catalogs or multi-device editing.

## Phase 3 Payments And Invoices

- Invoice table and PDF generation.
- Outstanding balances and credit limits.
- Payment records.
- Optional Stripe/local payment provider integration.

## Phase 4 Delivery And Driver

- Delivery routes.
- Driver app/role.
- Proof of delivery.
- Customer delivery notifications through WhatsApp.

## Phase 5 Analytics And ERP

- Completed MVP operational view: bounded period sales, top
  customer/product, low-stock, and manually recorded balance summaries.
- Future: scheduled exports, richer comparisons, and low-stock purchasing
  forecasts.
- Demand forecasting.
- ERP/accounting exports.
- Multi-branch inventory.

## Phase 2A Customer Shopping UI

- Completed modern customer UI pass and functional demo shopping flow.
- Completed product details, checkout, order history/reorder,
  customer-profile all-products discounts, banners, notifications, product
  upload, and responsive web/admin flows.
- The former standalone price-group and per-product special-pricing surface is
  retired. Its database tables remain dormant during the compatibility
  transition, while historical orders keep their original price snapshots.
- Next production activation: approved catalog/images, migrated client
  Supabase project, Firebase/APNs/web push, custom domain, and physical-device
  acceptance testing.
