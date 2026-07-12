# Offline Sync Plan

## Implemented In MVP

- Connectivity provider.
- Offline banner: `لا يوجد اتصال — سيتم حفظ التغييرات مؤقتاً`.
- Repository abstraction.
- Demo in-memory catalog and orders.
- Clear place to save offline order drafts.

## Phase 2

- Add Drift database.
- Cache products, categories, prices, profile, and recent orders.
- Add `sync_outbox` records for offline orders and customer notes.
- Submit outbox when connection returns.
- Show draft/syncing/failed state per order.
- Resolve product price conflicts by using server price at final confirmation and showing admin confirmation.

## Local Tables

- `cached_products`
- `cached_categories`
- `cached_prices`
- `draft_orders`
- `draft_order_items`
- `sync_outbox`

## Rules

- Customer can browse cached catalog offline.
- Customer can edit cart offline.
- Offline order is a draft until synced.
- Server decides final order status and price confirmation.
