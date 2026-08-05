# Deployment and migration safety

## Verified deployment state

- Vercel serves the GoStay frontend and currently includes the refactored
  `environment.js` and `api-client.js` scripts.
- Supabase production exposes two Edge Functions: `api` and `recommend-rooms`.
- The deployed `api` function returns the expected structured `not_found`
  response for an empty route request.
- Edge Functions have not been redeployed from `backend/supabase` as part of
  this work.

## Debug page

`frontend/database-test.html` is a development diagnostic. Both repository-root
and frontend-root `.vercelignore` files exclude it for the two common Vercel
root-directory configurations. Its JavaScript also refuses to query the API
unless the hostname is `localhost`, `127.0.0.1` or `::1`.

After the next Vercel deployment, verify that `/database-test.html` returns 404.

## Migration gate

Migration versions must be unique. Run:

```bash
npm run check:migrations
```

The former duplicate versions were ordered as:

```text
20260727000300_catalog_rls_and_privilege_hardening.sql
20260727000301_profiles_rls_and_privilege_hardening.sql
```

Do not run `supabase db push` against production until all of the following are
complete:

1. Export the production schema and migration history.
2. Compare them with every repository migration.
3. Baseline or repair migration history without replaying applied DDL.
4. Review the SQL diff and rollback plan.
5. Run preflight checks against a development/staging copy.
6. Run Core Booking E2E, Admin E2E and Runtime Security.
7. Obtain explicit production approval.

The Supabase dashboard previously showed no recorded migrations while the live
schema contained the application objects. This mismatch is a hard blocker for
an automated production `db push`.
