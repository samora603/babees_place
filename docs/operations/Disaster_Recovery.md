# Disaster Recovery Notes

## RPO / RTO targets (recommended)

| Tier | RPO | RTO |
|---|---|---|
| Database | ≤ 24h (prefer PITR) | ≤ 4h |
| Frontend static | last green CI artifact | ≤ 1h |
| Secrets | vault / Supabase secrets | ≤ 1h |

Adjust to business needs before go-live.

## Backups

1. **Supabase:** enable PITR / daily backups on paid plans; otherwise schedule `pg_dump`
2. **Storage bucket `products`:** include in backup policy
3. **Frontend:** retain CI build artifacts (7+ days)

## Restore procedure (high level)

1. Declare incident; freeze deploys
2. Restore Postgres from backup/PITR to a staging project first when possible
3. Validate RLS + critical RPCs (`place_order`, payments finalize)
4. Point frontend env to restored project **or** restore in-place after snapshot
5. Smoke checkout + admin login
6. Post-incident: write audit note

## Data export (manual)

Admins can export audit logs from Health. For full DB dumps use Supabase dashboard / `pg_dump` — not the SPA.

## What is NOT covered yet

- Automated multi-region failover
- Full offline PWA commerce
- Live Sentry/OTel dashboards (stubs ready)
