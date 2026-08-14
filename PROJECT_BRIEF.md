# Project Brief

## Business Goal

Create a mobile ordering app for a Libyan B2B shop selling animal food, pet supplies, farm supplies, feed, accessories, medicine, supplements, litter, and cleaning products to business customers.

## Target Users

- Shop owner/admin: manages customers, customer-wide discounts, products,
  settings, and orders.
- Staff/sales employee: handles customers, product updates, and order status.
- Business customer: browses allowed catalog, sees prices, submits orders, and reviews order history.

## MVP Scope

- Login only, no public registration.
- Admin-created customer accounts.
- Secure WhatsApp invite message with temporary password as text and token-only invite link.
- Customer catalog, cart, checkout, orders, and profile.
- Optional percentage discount applied to every product for selected customers,
  managed from the customer's admin profile and resolved server-side.
- Admin dashboard, customers, products, orders, notifications, settings, and
  operational reports.
- Supabase schema, RLS policies, seed data, and Edge Function skeletons.
- Offline-ready architecture with simple demo behavior.

## Future Scope

- Richer multi-device offline editing and conflict resolution beyond the
  current account-scoped cache and safe order outbox.
- Invoices, payments, credit limits, and balances.
- Delivery/driver app.
- Barcode scanning and inventory receiving.
- ERP/accounting integration.
- Advanced promotions, coupons, or tiered pricing beyond the single
  customer-wide discount.
