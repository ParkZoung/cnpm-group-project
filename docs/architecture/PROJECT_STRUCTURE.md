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

## Migration rules

- Keep HTML routes stable while MVC modules are introduced.
- Preserve the existing API response contract during backend extraction.
- Do not move authorization out of RLS or security-definer RPCs.
- Do not run historical migrations against production until schema drift and
  migration history have been reconciled.
- Refactor one customer/admin feature at a time and run E2E tests after each.
