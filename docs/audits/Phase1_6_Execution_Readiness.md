# Phase 1.6 — Execution Readiness Assessment

**Date:** 2026-07-12
**Scope:** Readiness to execute the live-DB ↔ repo ↔ frontend reconciliation.
**Status:** Planning complete. **No migrations, SQL, live/frontend changes, or commits made.**
**Companion:** `docs/operations/Database_Reconciliation_Runbook.md` (the how-to).

---

## Executive Summary

The complete engineering package for reconciliation now exists: verified baseline
(1.6‑A), canonical schema + decision log (1.6‑B), and the operational runbook (1.6‑C).
A different engineer could execute the reconciliation from the runbook alone.

The work is **ready to execute on staging**, and **conditionally ready for production**
pending a small set of human actions (backups, two data-verification checks, and approvals
for the destructive/normalizing steps). The additive-first strategy means most of the change
is zero-downtime and reversible with `DROP`; only two late steps (M6 normalization, M7
structural) require a maintenance window and are reversible only via backup restore.

**Recommendation: GO** to begin execution on staging immediately; **conditional GO** for
production per the approvals and prerequisites below.

---

## Implementation Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `products` PK `(id,name)`→`(id)` fails if `id` not unique | Med | High | Run uniqueness check before M7; dedupe; window |
| `place_order` (M4) regresses checkout | Med | High | Validate on staging first; RPC derived from 001 + verified columns |
| Constraint adds (M5) fail on dirty data | Med | Med | Dedupe/verify before adding UNIQUE/CHECK |
| Frontend deployed ahead of its DB migration | Med | High | Enforce "DB first, then frontend" ordering (runbook §4) |
| Migration-history repair confusion (M0) | Low | Med | Follow M0 verification; `db diff` must be clean |
| Partial prod migration on failure | Low | High | One migration group at a time; rollback per §6; never leave half-migrated |

## Operational Risks

| Risk | Impact | Mitigation |
|---|---|---|
| No staging project available | Forces prod-window testing | Use `supabase db branch` or provision staging first |
| Maintenance window overrun (M6/M7) | User-facing downtime | Size window by row count (Unknown #1); low-traffic slot |
| Backup/restore not exercised | Slow recovery | Take + verify backups at start, pre‑M6, pre‑M7 |
| Docker unavailable for `db diff` | Blocks validation | Ensure Docker running on the operator machine |
| Storage bucket assumptions | Broken uploads | Verify bucket in dashboard before M8 |

## Manual Tasks (cannot be automated / not guessable)

1. Take + verify backups (start, pre‑M6, pre‑M7).
2. Read-only verifications (Readiness §Manual Steps, Phase 1.5): `products.id` uniqueness;
   `cart_items`/`wishlists` duplicates; `storage.buckets` for `products`; distinct `profiles.role` values.
3. Dashboard: confirm/lock storage bucket; harden Auth settings (password policy, email
   confirmation, captcha).
4. `migration repair` for the baseline (M0) — writes only to the migration-history table.
5. Product decision on `payments`/`pickup_locations`/`addresses` scope for Phase 2.
6. Promote/retire migration files (adopt baseline as `001_initial_schema.sql`, retire fictional 001, delete empty remote_schema file).

## Required Approvals

| # | Item | Approver |
|---|---|---|
| 1 | ADR-001 direction (adopt live as SoT) | Project owner |
| 2 | Production backup + window for M6/M7 | Owner / DBA |
| 3 | `products` PK change + `"Description"` rename (M7) | Owner / DBA |
| 4 | `profiles.role` normalization + CHECK (M6) | Owner |
| 5 | UNIQUE constraints (dedupe) (M5) | Owner |
| 6 | Phase 2 feature scope (payments/pickup/addresses) | Product owner |

Additive/safe steps (M0–M4 except gated data, M8) need only the go-ahead to begin + staging-first.

## Estimated Timeline

| Phase | Effort |
|---|---|
| Baseline adoption (M0) + branch setup | 0.5–1 day |
| Additive + security + RLS + functions (M1, M3, M2, M4) + paired frontend | 2–3 days |
| Integrity/indexes + storage (M5, M8) + frontend | 1–2 days |
| Normalization + structural (M6, M7) + windows | 1–2 days |
| Staging validation + prod deploy + soak | 1–2 days |
| **Total** | **~5–10 working days** (excludes Phase 2 feature tables) |

## Engineering Confidence

**High (8.5/10)** for the plan quality and coverage; **Medium** for execution certainty until
the four read-only verifications are run (they gate the two high-risk steps). The additive-first
design, per-step rollback, and staging gate substantially de-risk execution.

## Go / No-Go Recommendation

- **GO** — begin on staging now (M0–M5, M8 are additive/reversible).
- **CONDITIONAL GO (prod)** — proceed to production per migration group once: backups taken,
  the four verifications pass, and approvals #1–#5 are granted. **NO-GO for automated/unattended
  execution** and for M6/M7 without a window + backup.

## Remaining Unknowns

1. Row counts / data volume (sizes the M6/M7 window).
2. `products.id` uniqueness (blocks M7 PK change).
3. Duplicate cart/wishlist rows (blocks M5 UNIQUE).
4. Storage bucket `products` existence/visibility.
5. Payments provider/flow shape (Phase 2 `payments` design).
6. Whether any non-`public` objects the app relies on exist (none observed).

## Production Prerequisites

- CI green on the reconciliation PR(s).
- Staging validated end-to-end (Verification Checklist).
- Fresh prod backup + PITR snapshot.
- Approvals #1–#5 recorded; window scheduled for M6/M7.
- Rollback plan reviewed; operator has Supabase access + Docker.

---

## Final Validation (traceability assertion)

Per the workstream rules, verified across the Phase 1.6 documents:

- **Every reconciliation decision has an execution step** — each `Reconciliation_Decision_Log.md`
  decision (D-TBL/D-PROD/D-CUST/D-KEY/D-IDX/D-RLS/D-RPC/D-STOR/D-FEAT) maps to a migration
  `M0..M8` and/or a frontend rollout row (Runbook §2, §4). ✅
- **Every execution step has a validation step** — Runbook §1 (stage verification), §2
  (per-migration validation), and §5 (Verification Checklist). ✅
- **Every validation step has a rollback procedure** — Runbook §6 (per-stage rollback). ✅
- **Every rollback procedure has a defined trigger** — Runbook §1 stage "rollback trigger" +
  §6 "decision point". ✅
- **No unresolved Critical items undocumented** — the only Critical (C-1 role escalation) is
  covered by M3 with an immediate live-compatible fix (documented in
  `Phase1_Final_Closure_Report.md` and mapped to D-RLS-1). ✅

### Remaining manual actions that cannot be automated
1. Backups + verification (start / pre‑M6 / pre‑M7).
2. Read-only data verifications (id uniqueness, duplicates, roles, storage bucket).
3. Dashboard hardening (Auth settings) + bucket confirmation.
4. Approvals for M5/M6/M7 and Phase 2 feature scope.
5. Baseline file promotion + fictional-001 retirement + `migration repair`.
6. Scheduling the maintenance window for M6/M7.

**Stop:** Phase 1.6 Workstream C complete. Operational runbook + readiness assessment produced.
No migrations, SQL, live/frontend/backend changes, deployments, or commits were made.
