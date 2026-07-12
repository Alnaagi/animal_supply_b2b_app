# Data Model

All main records use UUID primary keys, `created_at`, `updated_at`, and archive/active flags where useful.

## Core Tables

- `profiles`: one row per Supabase Auth user, with role `admin`, `staff`, or `customer`.
- `business_customers`: B2B account, linked to the customer profile, price group, city, address, status, credit fields.
- `customer_contacts`: extra contacts for a business customer.
- `categories`: product categories with archive support.
- `products`: SKU-unique catalog items, stock, unit size, animal type, MOQ, active/archive flags.
- Demo/Phase 2 catalog fields include `name_en`, `brand`, `package_size`, `old_price`, `discount_percent`, `image_url`, `source_url`, `tags`, `is_featured`, and `is_top_selling`.
- `product_images`: image paths in Supabase Storage.
- `price_groups`: base/wholesale/special groups.
- `product_prices`: group-level price per product.
- `customer_special_prices`: customer-specific override price.
- `inventory_movements`: stock adjustments, receiving, sales reservations.
- `orders`: customer orders with status.
- `order_items`: product, quantity, price snapshot.
- `app_settings`: shop/app distribution settings.
- `banners`: offers and home banners.
- `invite_tokens`: one-time expiring invite tokens, no passwords.
- `audit_logs`: admin/staff actions.
- `sync_outbox`: future sync queue records.

## Relationships

- `profiles.id` equals `auth.users.id`.
- `business_customers.profile_id` references `profiles.id`.
- `business_customers.price_group_id` references `price_groups.id`.
- `orders.customer_id` references `business_customers.id`.
- `order_items.order_id` references `orders.id`.
- `order_items.product_id` references `products.id`.
- `product_prices.product_id` references `products.id`.
- `product_prices.price_group_id` references `price_groups.id`.
- `customer_special_prices.customer_id` references `business_customers.id`.
