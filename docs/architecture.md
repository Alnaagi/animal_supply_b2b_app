# Architecture Notes

The app keeps an explicit demo/offline-friendly mode while preserving the same
production security boundaries used by the Supabase implementation.

- UI calls Riverpod controllers/providers.
- Controllers call repository interfaces rather than querying Supabase from
  screens.
- Repositories select demo/local-cache or Supabase-backed behavior from public
  runtime configuration.
- Production order/catalog/customer lists use bounded repository pages;
  dashboard and report totals come from role-checked aggregate RPCs instead of
  loading an entire table into Flutter.
- Local cache and outbox persist customer-safe data; queued orders contain
  product IDs and quantities, not trusted final prices.
- Edge Functions handle Auth administration, invite/password operations,
  device-token registration, authoritative order transactions, privileged
  status changes, and notification delivery.
- RLS remains active for normal anon/authenticated client access, with customer
  policies scoped to `auth.uid()` and the linked business-customer profile.
- A customer forced to change a temporary password can bootstrap only minimal
  account state. Full business/contact rows remain RLS-blocked until a current
  one-time invite is redeemed and password completion succeeds.
- Service-role credentials and Firebase server credentials never enter Flutter,
  APK/IPA assets, web assets, URLs, logs, or documentation examples.

## Product pricing and inventory boundaries

The Arabic-first admin editor intentionally keeps the business-facing product
contract small:

- `اسم المنتج` maps to the product name and `اسم الشركة` maps to the company
  or brand.
- `سعر الجملة` maps to the base wholesale price. A customer's optional
  `business_customers.discount_percent` applies uniformly to all products, and
  the server-resolved effective wholesale price remains authoritative for cart
  and order totals.
- `products.discount_percent` is separate product-promotion metadata. It may
  support catalog presentation, but it is not the negotiated customer discount
  and must not independently alter authoritative order totals.
- `سعر بيع الوحدة المقترح` maps to `retail_unit_price`. It is a
  reference-only suggested resale price for one retail unit and must never be
  used in `unit_price`, `line_total`, subtotal, fees, reservations, or stock
  arithmetic.
- `الحد الأدنى لطلب الجملة` maps to the bulk MOQ. Optional
  `الكمية في العلبة` maps to `units_per_box` and is display/snapshot metadata;
  it does not multiply the sellable quantity or price.
- `تتبع المخزون` controls whether availability limits and delivery deductions
  apply. Tracked availability is total stock minus active tracked
  reservations. Untracked products remain orderable without a stock cap,
  retain auditable reservation/order records, and do not create a stock
  deduction or low-stock result.
- Customer visibility and archive state remain separate. For a tracked product
  below its MOQ, `hide_when_out_of_stock` either removes it from the customer
  catalog or leaves it visible and non-orderable as unavailable.

Migration `202607220031_simplified_product_controls.sql` owns these database
fields, historical order-item snapshots, supported-value constraints, catalog
RPC behavior, and the guard that prevents disabling tracking while active
tracked reservations exist.

Customer product reads remain protected by the active-account RLS helpers.
The product select policy and `SECURITY INVOKER` catalog RPCs expose only
active, non-archived customer-visible rows and enforce the configured
hide-when-unavailable behavior. Staff/admin visibility remains role-checked.
Neither Flutter nor offline/demo code receives a privilege bypass; queued
orders still send product IDs and quantities for server-side wholesale-price,
MOQ, and inventory validation.

The active administration flow manages the all-products discount from the
customer profile. The standalone pricing screen and its price-group and
per-product special-price controls are retired. The legacy `price_groups`,
`product_prices`, and `customer_special_prices` tables remain dormant during
the transition so existing data is not destructively removed and older
deployments can be handled safely. Active catalog and order pricing must ignore
those legacy overrides.

Order items continue to store the authoritative unit price charged when the
order was created. Changing a customer's current discount affects future
catalog and order calculations only; it never rewrites historical order
snapshots.

Production activation means migrating and RLS-testing the client-owned
Supabase project, configuring server-only function secrets, and supplying only
public anon/web values to Flutter. It must not move privileged operations into
the app.
