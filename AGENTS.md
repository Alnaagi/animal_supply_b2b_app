# Agent Rules

## Project Rules

- Keep UI Arabic-first and RTL.
- Customers never create their own accounts.
- No public sign-up screen.
- The MVP must remain usable in demo/offline-friendly mode when Supabase credentials are absent.
- Clearly label demo data, placeholder images, deferred sync, and production-only flows.
- Service role key must never appear in Flutter, mobile config, APK assets, logs, or docs examples.
- Do not place real passwords in URLs, QR codes, deep links, or app links.
- Invite links may contain only a one-time token and optional non-secret client code.
- Preserve existing production safety boundaries unless the task explicitly asks to change them.

## Architecture

- Flutter app lives in `app/`.
- Supabase SQL and Edge Functions live in `supabase/`.
- Feature folders live under `lib/src/features`.
- Shared configuration, routing, theme, connectivity, and constants live under `lib/src/core`.
- Models, repositories, local cache, remote clients, and sync boundaries live under `lib/src/data`.
- Use Riverpod providers for state and repository access.
- Use GoRouter for role-based routes.
- Keep Supabase access behind repositories, remote clients, or Edge Functions. Screens should not bypass those boundaries.
- Do not rewrite unrelated architecture, routing, repository contracts, or auth flow while solving a narrow task.

## Coding Style

- Prefer small widgets and repository boundaries.
- Keep business rules out of screens when they grow.
- Keep comments in English for technical notes.
- Use Arabic labels and Libyan-friendly wording in UI.

## Run And Test

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

If the local Flutter SDK path is needed:

```bash
cd /home/alnaagi/Desktop/animal_supply_b2b_app/app
/home/alnaagi/development/flutter/bin/flutter pub get
/home/alnaagi/development/flutter/bin/flutter analyze
/home/alnaagi/development/flutter/bin/flutter test
```

If a command cannot be run, report why and what risk remains.

## Supabase Rules

- Admin-only work that needs service role runs in Edge Functions.
- Flutter uses anon key only.
- RLS protects every table.
- Customer policies must be scoped to `auth.uid()` and `business_customers.profile_id`.
- Staff/admin checks must use a helper function reading `profiles.role`.
- Auth user creation, password reset, invite issuance, and privileged customer/account operations must stay server-side.
- Offline/cache/outbox work must not weaken RLS or create client-side service-role shortcuts.

## What Not To Do

- Do not add customer self-registration.
- Do not store service role in `.env` shipped to app.
- Do not put temporary passwords in invite links.
- Do not bypass RLS from the client.
- Do not silently turn placeholders into insecure production shortcuts.
- Do not replace Arabic RTL copy with English-only UI unless explicitly asked.
- Do not remove demo-mode safety while Supabase is unconfigured.

## Acceptance Criteria

Before handoff, report:

- user workflow tested
- Arabic/RTL impact
- Supabase/RLS impact
- demo/offline behavior impact
- commands run
- files changed
- known limitations and deferred work
