# Testing Plan

## Automated

- Widget test for login screen.
- Unit tests for cart totals and order creation.
- Repository tests for demo and Supabase implementations.
- RLS tests with Supabase local CLI.
- Edge Function tests for admin-only access and token safety.

## Manual

- Login as admin, staff, customer.
- Confirm customer cannot see admin routes.
- Add products to cart and submit order.
- Check order history.
- Generate WhatsApp invite and verify no password appears in link.
- Disable internet and confirm offline banner.
- Build debug APK.

## Security Tests

- Try customer reading another customer order.
- Try customer updating order status.
- Try anonymous read of private tables.
- Confirm service role key is absent from Flutter files.
