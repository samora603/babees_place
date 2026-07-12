# Migration History

**Last updated:** 2026-07-12 (Phase 1.7A — Baseline Adoption)
**Live project:** `qfcygrxrfszcdltangec` ("Babis-place")
**Live migration history:** **empty** — the live database was built manually; no migration
has ever been recorded on the remote `supabase_migrations.schema_migrations` table.

This document is the authoritative record of the repository's migration files and their
status. Classification values: **Active** (part of the forward sequence), **Archived**
(preserved for history, never applied), **Deprecated** (superseded/fictional; do not apply).

---

## Active migration sequence

| Order | Version / File | Purpose | Applied on live? | Notes |
|---|---|---|---|---|
| 1 | `supabase/migrations/001_initial_schema.sql` | Official baseline — faithful snapshot of the current live `public` schema (7 tables, `order_status` enum, PKs, 2 FKs, RLS enable, 10 policies, grants) | **No** (requires `migration repair` — reconciliation step, not done in 1.7A) | Source of truth for all future migrations. Only a provenance comment header was added to the pg_dump. |

> No forward migrations (`M1..M8` in `Migration_Strategy.md`) have been authored yet. They
> will be created **after** baseline adoption is confirmed on live (Phase 1.7B+).

---

## Archived / deprecated migrations

Located in `supabase/migrations/archive/` (see its `README.md`). **None were ever applied to
live** and none may be applied.

| File | Classification | Reason | Intent carried forward as |
|---|---|---|---|
| `001_schema_rls_place_order.sql` | Deprecated (fictional) | Never-applied idealized schema; diverges from live on tables, columns, PKs, and functions | Baseline (`001_initial_schema.sql`) + `M1`/`M4` |
| `002_phase1_security_hardening.sql` | Deprecated | Forward-fix targeting the fictional `001`; objects absent on live; `DO NOT APPLY AS-IS` header | `M3` (profiles role escalation) + `M2` (RLS) |
| `003_phase1_indexes_constraints.sql` | Deprecated | Forward-fix targeting the fictional `001`; references non-existent live columns/tables | `M5` (FK/UNIQUE/CHECK/index) |
| `20260617042152_remote_schema.sql` | Archived (empty placeholder) | 0-byte artifact of an earlier empty `db pull` | Replaced by the baseline |

---

## Provenance

- The baseline was generated read-only in Phase 1.6 Workstream A via
  `supabase db dump --linked -s public` and verified in
  `docs/database/Baseline_Migration_Verification.md`.
- The pristine generated artifact remains at
  `docs/database/generated_baseline/001_initial_schema.sql` (unmodified source of truth).
- The adopted copy at `supabase/migrations/001_initial_schema.sql` is byte-identical to that
  artifact except for an added provenance comment header.

---

## Naming convention (going forward)

- Baseline keeps the numeric `001_` prefix to match all approved planning documents.
- Forward migrations should use Supabase timestamped versions
  (`<YYYYMMDDHHMMSS>_<description>.sql`) generated with `supabase migration new <name>`,
  authored against the `M0..M8` plan in `Migration_Strategy.md`.
- `snake_case`, descriptive names; one logical change set per migration.

---

## Remaining work before forward migrations can be authored

1. **Adopt baseline on live** (reconciliation, not done here): run
   `supabase migration repair --status applied 001` so the live history records the baseline,
   then confirm `supabase db diff --linked` is clean. (Runbook §1 Stage 2 / `M0`.)
2. Run the four read-only verifications (product `id` uniqueness, cart/wishlist duplicates,
   storage bucket, distinct `profiles.role`) — gate the high-risk migrations.
3. Obtain approvals for `M5`/`M6`/`M7` (see `Phase1_6_Execution_Readiness.md`).
4. Only then author `M1..M8` as new timestamped migrations.
