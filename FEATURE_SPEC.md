# Feature Spec

## Auth

- Login with username/email/phone and password.
- Optional invite token/client code field.
- Remember session through Supabase Auth.
- Forgot password text tells customer to contact the shop/admin.
- No public registration screen.

## Customer Home

- Welcome card with business name.
- Quick search entry.
- Categories.
- Featured products.
- Latest offers placeholder.
- Reorder last order.
- WhatsApp support action.

## Catalog

- Product list with image placeholder, name, SKU, price, stock status.
- Search.
- Category support.
- Filter placeholders for brand, animal type, size, price, availability.
- Customer-specific pricing architecture through price tables.

## Product Details

- Images, description, SKU, category, animal type, unit size, stock, price, MOQ.
- Add to cart.
- Current MVP shows details inside product cards; a dedicated detail route is planned.

## Cart And Checkout

- Quantity update.
- Remove item.
- Subtotal in LYD.
- Delivery note placeholder.
- Customer note field.
- Submit order with `pending` status.
- Confirmation dialog.
- WhatsApp share placeholder.

## Orders

- History.
- Details.
- Status display.
- Reorder button.

## Profile

- Business name, contact, phone, city/area, address.
- Price group, status.
- Credit limit and outstanding balance placeholders.

## Admin Dashboard

- Customer count, pending orders, today orders, low stock count.
- Quick actions.

## Customer Management

- Create/edit customer placeholders.
- Activate/suspend placeholder.
- Price group, city/area, credit limit placeholders.
- Reset password flow planned via Edge Function.
- Generate invite token and WhatsApp message.

## Product Management

- List products.
- Add/edit/archive placeholders.
- Image upload placeholder.
- SKU, barcode, category, animal type, unit size, base price, stock, MOQ, active status.

## Categories And Price Groups

- Tables and docs are present.
- MVP UI can be expanded from admin products/settings.

## Order Management

- List orders.
- Filter placeholders.
- View detail.
- Status change placeholder.
- Admin note and WhatsApp customer placeholder.

## Settings And Reports

- Shop name, phone, app/APK links, delivery policy, minimum order, currency, maintenance mode.
- Reports placeholders: daily sales, top customers, top products, low stock, unpaid balances.

## Phase 2A UI/UX Shopping Upgrade

- Customer UI upgraded with original premium Arabic B2B shopping screens.
- Product details, cart, checkout, order history, and reorder are functional in demo mode.
- Product catalog now includes 40 demo products with brand, stock, MOQ, old price/discount, top-selling and featured flags.

## Demo Catalog Phase

- Product catalog now includes 40 realistic demo products across 8 categories.
- Every product has Arabic display fields, SKU, brand, category, package size, stock, MOQ, tags, and demo price.
- Images use external placeholder URLs with in-app fallback UI.
- Search supports Arabic name, English name, SKU, brand, category, and tags.
