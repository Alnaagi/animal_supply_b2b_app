# Supabase Plan

## Auth

Supabase Auth manages sessions. Customers are not allowed to sign up. Admin-only Edge Functions create Auth users with generated temporary passwords, insert `profiles`, create `business_customers`, and return invite text.

## RLS

RLS is enabled on all app tables. Helper functions check current role and current business customer id. Admin can manage everything. Staff can manage products, customers, and orders. Customers can only read their own account, visible active catalog, scoped prices, and their own orders.

## Storage

Bucket: `product-images`.

- Public read can be used for MVP if images are not sensitive.
- Writes should be restricted to admin/staff.
- Store path in `product_images.storage_path`.
- Demo product rows may use external placeholder `image_url`; production should replace these with client-approved Supabase Storage images or licensed supplier URLs.

## Edge Functions

- `admin-create-customer`: admin/staff only, creates Auth user and records, returns temporary password and safe invite.
- `admin-reset-customer-password`: admin/staff only, sets temporary password and `must_change_password`.
- `generate-invite-token`: admin/staff only, creates one-time expiring token.
- `send-admin-notification`: stores admin/staff notification records for new orders and is the server-side integration point for Firebase Cloud Messaging HTTP v1.

## Admin Operations Additions

- `admin_device_tokens`: stores admin/staff FCM tokens per device.
- `notifications`: stores notification center records so alerts are visible even if push delivery fails.
- `app_versions`: controls direct APK update prompts, required update state, APK URL, and release notes.
- `banners`: now supports `image_url`, CTA text, target type/value, and sort order for customer home banners.

Flutter should use normal Supabase anon client + RLS for table access. Service role credentials and Firebase server credentials remain only in Edge Functions.

## Production Notes

- Service role key belongs only in Supabase Function secrets.
- Use short token expiry, hashed tokens, rate limits, and audit logs.
- Require customers to change temporary password on first login.
