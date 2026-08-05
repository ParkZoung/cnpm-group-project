# GoStay backend

The backend is a Supabase project kept under `backend/supabase` so the repository
has an explicit frontend/backend boundary while preserving the directory layout
expected by the Supabase CLI.

## Local commands

Run these commands from the repository root:

```bash
npm run backend:start
npm run backend:serve:api
npm run backend:serve:recommendations
npm run backend:stop
```

`npm run backend:db:push` changes the linked database. Review migrations and the
target project before running it. Production migrations are not applied as part
of the repository restructuring.

## Structure

```text
backend/supabase/
├── config.toml
├── functions/
│   ├── _shared/
│   ├── api/
│   └── recommend-rooms/
├── migrations/
├── preflight/
├── rollbacks/
└── seeds/
```

The API entry point delegates HTTP handling to controllers. Authentication is
implemented as middleware, database access is isolated in repositories, and
request shape checks live in validators. PostgreSQL RLS and reviewed RPCs remain
the final authorization and data-integrity boundary.
