# GoStay Database Notes

## Scope

This document describes the database used by the deployed GoStay application.
Executable changes belong in `backend/supabase/migrations`; this file must never
be executed as SQL.

## Public schema

The production schema contains 11 application tables:

1. `profiles`
2. `branches`
3. `room_types`
4. `rooms`
5. `bookings`
6. `promotions`
7. `room_images`
8. `amenities`
9. `room_amenities`
10. `promotion_usages`
11. `booking_status_history`

Main relationships:

```text
auth.users 1---1 profiles
branches 1---n rooms
room_types 1---n rooms
rooms 1---n room_images
rooms n---n amenities (room_amenities)
profiles 1---n bookings
rooms 1---n bookings
promotions 1---n bookings
bookings 1---n booking_status_history
```

## Security boundary

The browser does not hold a Supabase database key. It calls the `api` Edge
Function, which forwards the user's JWT through the Supabase SDK. PostgreSQL RLS
and reviewed RPCs are the final authorization and integrity controls.

Repository migrations explicitly enable and configure RLS for:

- `profiles`: own-profile access plus admin access.
- `bookings`: customer ownership plus admin access.
- `branches`, `room_types`, `rooms`, `promotions`, `room_images`, `amenities`
  and `room_amenities`: public catalog reads and admin writes.

The current repository does not yet contain a complete baseline migration for
the original creation and policy history of `promotion_usages` and
`booking_status_history`. Their live state must be included in schema
reconciliation before production migration automation is enabled.

## Reviewed functions and RPCs

Authentication/profile foundation:

- `handle_new_auth_user`
- `is_admin`
- trigger `on_auth_user_created`

Application RPCs exposed by the Edge Function allowlist:

- `search_available_rooms` — public availability search.
- `create_booking` — authenticated, transactional booking creation.
- `cancel_own_booking` — customer cancellation of an owned booking.
- `admin_update_booking_status`
- `admin_update_payment_status`
- `admin_set_profile_role`
- `admin_set_profile_status`

The frontend must not replace these operations with unrestricted table writes.

## Real request flows

Customer booking:

```text
search form
  -> search_available_rooms
  -> room detail and local cart
  -> create_booking
  -> booking history
  -> cancel_own_booking
```

Administration:

```text
admin authentication
  -> RLS-protected catalog/profile reads
  -> reviewed admin RPC or RLS-protected mutation
  -> audit/status data returned to the UI
```

AI recommendations:

```text
browser -> api Edge Function -> recommend-rooms Edge Function
        -> catalog/availability data -> Gemini ranking
```

AI ranks real eligible rooms; it must not invent room IDs or prices.

## Migration state

Migration files are stored in `backend/supabase/migrations` and use unique
14-digit versions. Catalog hardening runs before profile hardening:

```text
20260727000300_catalog_rls_and_privilege_hardening.sql
20260727000301_profiles_rls_and_privilege_hardening.sql
```

The Supabase production dashboard has not shown a matching migration history,
even though the live database contains the schema and reviewed RPCs. Therefore:

- Do not run `supabase db push` against production.
- Export and diff the live schema first.
- Establish a reviewed baseline/repair plan.
- Preserve all existing RLS policies and RPC security semantics.

See `docs/architecture/DEPLOYMENT_SAFETY.md` for the production gate.
