# GoStay project structure

## Repository boundary

```text
frontend/          Browser application
backend/supabase/  Edge Functions, database migrations and deployment config
tests/             End-to-end and runtime security tests
docs/              Product, architecture, database and testing documentation
```

Moving the Supabase project under `backend/` is an organizational change only.
It does not rename the Supabase platform, environment variables, npm packages,
deployed function names or production URLs.

## Request flow

```text
HTML -> page controller -> frontend service/API client -> Edge Function API
     -> controller -> repository/RPC -> PostgreSQL
```

The legacy `window.gostaySupabase` facade is retained while pages are migrated
incrementally. Network transport now lives in `frontend/js/core/api-client.js`,
and public runtime configuration lives in `frontend/js/config/environment.js`.
Booking creation and cancellation are the first migrated slice and use
`frontend/js/services/booking-api.js`. Catalog, profile and admin screens remain
on the compatibility facade until they can be moved and tested separately.

## Current application flow

```text
Search -> search_available_rooms RPC -> room detail -> local cart
       -> booking-api -> create_booking RPC -> booking history
       -> booking-api -> cancel_own_booking RPC
```

Admin mutations continue to use reviewed admin RPCs. RLS and RPC authorization
remain unchanged and are verified by `npm run test:security`.

## Migration rules

- Keep HTML routes stable while MVC modules are introduced.
- Preserve the existing API response contract during backend extraction.
- Do not move authorization out of RLS or security-definer RPCs.
- Do not run historical migrations against production until schema drift and
  migration history have been reconciled.
- Refactor one customer/admin feature at a time and run E2E tests after each.

## Deferred naming cleanup

The files `admin-products.html` and `admin-categories.html` currently implement
room and branch management. Rename them to `admin-rooms.html` and
`admin-branches.html`, and split CSS by feature, only after the MVP/demo is
stable. Renaming now would change public routes, navigation links and E2E paths.
