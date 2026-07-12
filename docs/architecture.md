# Architecture Notes

The app is mock-first for MVP but shaped for Supabase production.

- UI calls Riverpod controllers.
- Controllers call repositories.
- Repositories later choose remote Supabase or local Drift cache.
- Edge Functions handle privileged account creation/reset.
- RLS remains active for normal client access.

Production repository work should add Supabase query implementations beside the existing demo repositories instead of moving service-role operations into Flutter.
