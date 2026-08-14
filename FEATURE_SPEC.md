# Feature Spec

## Auth

- Login with the admin-issued username or account email and password.
- Optional invite token/client code field.
- Remember session through Supabase Auth.
- Forgot password text tells customer to contact the shop/admin.
- No public registration screen.

## Customer Home

- Welcome card with business name.
- Quick search entry.
- Categories.
- Featured products.
- Admin-managed promotional banners and latest offers.
- Reorder last order.
- WhatsApp support action.

## Catalog

- Product list with approved uploaded/external image support and placeholder
  fallback, product name, company name, authoritative wholesale price, and
  stock/orderability status.
- Optional suggested single-unit retail price is reference-only for the
  reseller. It never changes cart, checkout, or order totals.
- Search by product or company name.
- Category support.
- Responsive filters for brand, animal type, package/unit size, price range,
  and availability.
- Bounded server-side paging in production with an offline-friendly cached
  snapshot and Arabic load-more controls.
- Each customer may have one optional percentage discount that applies to all
  products. The server resolves the discounted wholesale price from the
  customer profile.

## Product Details

- Product and company name, authoritative wholesale price, reference-only
  single-unit retail price, bulk minimum order quantity, stock status, and
  optional units per box.
- Units per box is omitted when the admin leaves it empty and never multiplies
  price or inventory quantities.
- Add to cart.
- Dedicated responsive product-detail route.

## Cart And Checkout

- Quantity update.
- Remove item.
- Subtotal in LYD.
- Totals use only the server-resolved wholesale/effective price. The suggested
  retail unit price is display metadata and is never charged.
- Customer note field.
- Submit order with `pending` status.
- Confirmation dialog.
- Copy/share order summary.

## Orders

- History.
- Details.
- Status display.
- Reorder button.

## Profile

- Business name, contact, phone, city/area, address.
- Customer-wide product discount and account status.
- Credit limit and outstanding balance as explicitly manual reference fields;
  they are not an accounting ledger or automatic credit decision.
- Visible push-notification permission/status control.

## Admin Dashboard

- Customer count, pending orders, today orders, low stock count.
- Quick actions.

## Customer Management

- Create and edit customer profiles through repository/Edge boundaries.
- Activate, suspend, archive, and restore.
- Set the optional all-products discount, city/area, and account controls from
  the customer profile.
- Reset password through an Edge Function.
- Generate one-time invite token and WhatsApp message; no password is placed
  in the invite URL.

## Product Management

- List, add, edit, archive, and restore products.
- The simplified Arabic-first add/edit form exposes only:
  `اسم المنتج`, `اسم الشركة`, `سعر الجملة`,
  `سعر بيع الوحدة المقترح`, `الحد الأدنى لطلب الجملة`, optional
  `الكمية في العلبة`, `تتبع المخزون`, tracked stock quantity,
  customer visibility, and the hide/show-when-unavailable choice.
- `سعر الجملة` is the base wholesale price used by authoritative
  server-side pricing. `سعر بيع الوحدة المقترح` is a reseller reference only.
- `products.discount_percent` and `old_price` remain optional product-promotion
  display metadata. They do not define or replace the customer-wide discount.
- When stock tracking is enabled, availability is total stock minus active
  tracked reservations. A product below its bulk MOQ is either hidden from
  customers or shown as unavailable, according to the admin toggle.
- When stock tracking is disabled, orders remain auditable but are not capped
  by, deducted from, or reported as low stock.
- Customer visibility is separate from archive/restore. Archived products
  remain unavailable until explicitly restored.
- Existing image and legacy catalog metadata can remain stored for
  compatibility, but they are not required fields in the simplified editor.

## Categories And Customer Discounts

- Categories remain managed with their product visibility and archive rules.
- The standalone pricing page, price-group administration, and per-product
  customer pricing are not part of the active app workflow.
- An admin sets one optional percentage discount from the customer profile; it
  applies uniformly to all active products and is resolved server-side from the
  base wholesale price.
- Legacy price-group, group-price, and customer-special-price tables remain
  dormant during the transition. Existing rows are retained for compatibility
  and are not treated as active pricing rules.
- Existing order items keep their original authoritative unit-price snapshots,
  so later customer-discount changes do not rewrite order history.

## Order Management

- Bounded, newest-first order paging.
- Server-side date/status filters and scoped deep-link lookup.
- View detail.
- Controlled server-side status transitions and status history.
- Customer status notifications and admin notes.
- Historical order totals and line prices remain immutable snapshots even when
  the customer's current all-products discount changes.

## Settings And Reports

- Shop name, phone, onboarding/download page, direct APK link, delivery
  policy, minimum order, fees, currency, and maintenance mode.
- Separate Android and iOS release metadata, optional/required updates, release
  notes, checksum, file size, and platform-appropriate distribution link.
- Operational reports for period sales, top customers, top products, low
  stock, and manually recorded balances. Production totals are calculated by
  bounded server-side aggregate RPCs.

## Phase 2A UI/UX Shopping Upgrade

- Customer UI upgraded with original premium Arabic B2B shopping screens.
- Product details, cart, checkout, order history, and reorder are functional in demo mode.
- Product catalog now includes 40 demo products with brand, stock, MOQ, old price/discount, top-selling and featured flags.

## Demo Catalog Phase

- Product catalog now includes 40 realistic demo products across 8 categories.
- Every product has Arabic display fields, SKU, brand, category, package size, stock, MOQ, tags, and demo price.
- Images use external placeholder URLs with in-app fallback UI.
- Search supports Arabic name, English name, SKU, brand, category, and tags.
