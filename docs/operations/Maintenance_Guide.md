# Maintenance Guide

## Routine

| Cadence | Task |
|---|---|
| Weekly | Review `/admin/health`, low stock, failed payments |
| Weekly | Dependency updates (`npm outdated`) on a branch + CI |
| Monthly | Rotate any Edge Function secrets |
| Per release | Apply new migrations on staging first |
| Per release | Confirm CI green; deploy `frontend/dist` |

## Safe change process

1. Feature branch
2. Tests + lint locally
3. PR → CI
4. Staging migrate + smoke
5. Production migrate (if needed) then frontend deploy

## Schema changes

- Prefer additive migrations (`NNN_*.sql`)
- Never edit applied migrations in place
- Document in `Migration_History.md`

## Feature flags / providers

Swap providers via env without code changes:

- Payments: `VITE_PAYMENT_PROVIDER`
- Email/SMS: `VITE_EMAIL_PROVIDER` / `VITE_SMS_PROVIDER`
- Errors: `VITE_ERROR_PROVIDER`

## Deprecations

When removing a table/RPC: soft-deprecate one release, then drop in a later migration.
