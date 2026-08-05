# GoStay domain terminology

Code, SQL and API payloads use the canonical English values below. Vietnamese
labels are presentation text only and must not introduce additional values.

## Roles

| Value | Meaning |
|---|---|
| `customer` | Customer who searches, books and manages their own bookings. |
| `staff` | Active staff member operating in a selected branch session. |
| `admin` | Active administrator managing catalog, bookings and access. |

## Profile status

- `active`: account may use capabilities allowed by its role.
- `inactive`: account is not currently active.
- `blocked`: access is administratively blocked.

## Booking status

- `pending`: booking awaits confirmation.
- `confirmed`: booking is confirmed and holds inventory.
- `checked_in`: guest has checked in.
- `completed`: stay has checked out/completed.
- `cancelled`: booking was cancelled.

Inventory is held by `pending`, `confirmed` and `checked_in`. Transitions are
enforced by PostgreSQL RPCs; frontend labels do not define transition rules.

## Payment status and option

- Payment status: `unpaid`, `pending`, `partially_paid`, `paid`, `failed`,
  `refunded`.
- Payment option: `deposit` or `full`.

The database calculates authoritative amounts. A customer payment claim is not
payment approval; Staff must review it before paid amounts are credited.

## Online check-in status

- `not_started`: online check-in exists but no payment has been claimed.
- `payment_claimed`: customer reports that a transfer was made.
- `approved`: Staff approved payment and a check-in token may be used.
- `rejected`: Staff rejected the claim with a reason.
- `consumed`: the one-time check-in token has been used.
- `expired`: the online check-in credential is no longer valid.

## Naming rules

- Use **booking** for the reservation aggregate and `booking_status` for its
  lifecycle.
- Use **payment transaction** for recorded money movement and `payment_status`
  for the aggregate payment state.
- Use **online check-in** for the VietQR/payment-claim workflow.
- `window.gostaySupabase` means the API compatibility facade, never a direct
  browser-to-database connection.
