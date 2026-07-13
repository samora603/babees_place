# Deployment — Technical Reference

**Status:** Updated in Workstream 9. Canonical how-to: `docs/operations/Deployment_Guide.md`.

---

## Current state

- Frontend: Vite React SPA (`frontend/`) — `npm run build` → `dist/`
- Backend: Supabase (Auth, PostgREST, Storage, RPCs)
- CI: `.github/workflows/ci.yml` — lint, test, build, artifact upload
- Deploy workflow stub: `.github/workflows/deploy.yml` (manual checklist gate)
- Ops docs: `docs/operations/` (deploy, runbook, DR, maintenance)
- Health: `/admin/health`
- Migrations authored through `019_operations.sql` (apply on target before go-live)

## Env (public only)

See `frontend/.env.example`. Required: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.

## Pre-deploy

Use checklists in `docs/audits/Workstream9_Production_Readiness_Report.md` and `docs/10_Final_Checklist.md`.

## Monitoring

- Client: `logger` + `errorReportingService` (Sentry/OTel stubs)
- Admin: health probes + audit log exports
