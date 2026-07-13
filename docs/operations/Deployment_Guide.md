# Deployment Guide

**Audience:** operators deploying Babees Place storefront + Supabase  
**Last updated:** Workstream 9

---

## Architecture (runtime)

```
Browser (Vite/React SPA)
  → Supabase Auth / PostgREST / Storage / RPCs
  → (future) Edge Functions: M-Pesa, email, SMS
```

There is no custom Node API. Secrets must never ship in `VITE_*` variables.

---

## Prerequisites

1. Node 20+
2. Supabase project (linked or remote URL + anon key)
3. Migrations `001`–`019` authored in repo (apply in order on target DB)
4. Green CI on the commit you deploy

---

## Environment

Copy `frontend/.env.example` → `frontend/.env`:

| Variable | Required | Notes |
|---|---|---|
| `VITE_SUPABASE_URL` | Yes | Project URL |
| `VITE_SUPABASE_ANON_KEY` | Yes | **Public** anon key only |
| `VITE_PAYMENT_PROVIDER` | No | `mock` (default) \| `daraja` |
| `VITE_EMAIL_PROVIDER` / `VITE_SMS_PROVIDER` | No | `mock` default |
| `VITE_LOG_LEVEL` | No | `info` recommended in prod |
| `VITE_ERROR_PROVIDER` | No | `console` until Sentry wired |
| `VITE_ENABLE_SW` | No | `true` to register `/sw.js` |

**Never set** `service_role` keys, M-Pesa passkeys, Resend/Twilio secrets in Vite env.

---

## Build

```bash
cd frontend
npm ci
npm run lint
npm run test
npm run build
```

Output: `frontend/dist/` — static hosting (Vercel, Netlify, Cloudflare Pages, S3+CDN).

SPA fallback: route all paths to `index.html`.

---

## Database cutover

1. Backup production Postgres
2. Apply migrations in order through `019_operations.sql`
3. Verify RLS with a non-admin authenticated user
4. Confirm `place_order`, payments, notifications, rewards RPCs

See `docs/database/Migration_History.md`.

---

## Post-deploy smoke

1. Home + Shop load
2. Register / login
3. Add to cart → checkout COD
4. Admin health page (`/admin/health`) shows DB OK
5. Payment mock path (if not live Daraja yet)

---

## Rollback

1. Revert frontend deploy to previous artifact
2. Database: restore from backup (forward migrations are preferred; avoid destructive down migrations)

---

## Related docs

- `docs/operations/Operational_Runbook.md`
- `docs/operations/Disaster_Recovery.md`
- `docs/operations/Maintenance_Guide.md`
- `docs/audits/Workstream9_Production_Readiness_Report.md`
