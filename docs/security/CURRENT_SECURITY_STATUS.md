# GoStay current security status

## Verification record

- Date: 2026-08-06 (Asia/Bangkok).
- Repository commit: `d6c648f468838c2c0d242fa20422f60856c15108`.
- Local environment: static repository inspection plus syntax, migration and
  contract checks.
- Supabase environment: production project `wpecaxsuadawaxadxqhj`, inspected
  read-only through Supabase Dashboard; no SQL or configuration was changed.

## Verified controls

- Authentication uses Supabase Auth through the `api` Edge Function.
- Protected API routes validate bearer tokens using `auth.getUser()`.
- `window.gostaySupabase` is an API facade and does not contain a Supabase key.
- Exposed tables and RPCs are allowlisted by the API.
- Production shows RLS enabled with customer, staff and admin policies on the
  principal application tables.
- Booking prices and ownership are established by PostgreSQL RPCs.
- The database contains concurrency protection against duplicate active stays.
- Production exposes Edge Functions `api` and `recommend-rooms`.

## Open findings

- Production migration history records 14 entries while this commit contains
  17 migration files. Schema objects corresponding to repository migrations
  `20260805000800`–`20260805001000` exist, but their history rows are absent.
- Production version `20260805000500` is recorded as `room_image_storage`, while
  the repository uses that version for `admin_profiles_with_email`.
- Supabase Security Advisor reported 0 errors, 30 warnings and 3 informational
  notices.
  Warnings include mutable `search_path` on `set_updated_at`, public execution
  of `rls_auto_enable`, broad public listing of `room-images`, and authenticated
  execution grants on several `SECURITY DEFINER` RPCs.
- Dashboard did not show a configured backup or staging branch/project.
- The new Postgres logs view returned no rows during inspection, so overview
  error counts could not be attributed.

## Current conclusion

The repository is materially hardened compared with the archived Stage 1 audit
and is suitable for the existing MVP demo flow. It is not yet safe to replay or
automatically push production migrations. Production migration history must be
reconciled and authorization must be runtime-tested on an isolated staging
environment before the next database release.
