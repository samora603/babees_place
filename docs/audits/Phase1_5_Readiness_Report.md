# Phase 1.5 — Live Database Reconciliation Readiness Report

**Date:** 2026-07-12
**Live project:** `qfcygrxrfszcdltangec` ("Babis-place", eu-central-1, Postgres 17.6)
**Status:** Planning complete. **No database or code changes were made in this phase.**
**Companion docs:** `Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`,
`Migration_Strategy.md`, `Frontend_Database_Compatibility.md`, `ADR-001-Database-Reconciliation.md`.

---

## Executive summary

The comparison, canonical proposal, compatibility audit, migration strategy, and ADR are
complete and evidence-based. A human engineer can now execute the reconciliation knowing
exactly what changes, why, and how to recover. Reconciliation is **not yet ready to run
end-to-end** because three preconditions require live/human actions: a backup, a `db pull`
baseline, and two data-level verifications (storage bucket, `products.id` uniqueness).

---

## Workstream E — Security Review (of the canonical schema)

Does the proposed canonical schema support a secure posture? Assessment:

| Control | Canonical supports it? | Notes / residual risk |
|---|---|---|
| Secure RLS on every table | ✅ (planned) | M2 adds owner policies for `cart_items`/`wishlists`; public read + admin write for `categories`/`products`. **Risk today:** those tables are deny-all until M2. |
| Role-escalation prevention | ✅ | M3 adds `WITH CHECK` blocking role self-edit + admin-only role updates. **Live is vulnerable until M3 applied.** |
| Admin authorization | ✅ | `is_admin()` (M4) centralizes checks; admin policies reference it. Frontend `AdminRoute` is UX-only (correct). |
| Customer authorization | ✅ | Owner scoping on cart/wishlist/orders/order_items/profiles. |
| Order integrity (server-side totals) | ✅ | `place_order()` (M4) recomputes totals from live prices + `FOR UPDATE`; `order_items` direct INSERT stays blocked. |
| Least privilege | 🟡 | Live grants `ALL` to `anon`/`authenticated` on all tables (default Supabase grants); RLS is the real gate. Consider tightening grants, but RLS-first is acceptable. |
| Secure Storage policies | ❓ | **Unverified.** No user-defined `storage.objects` policies exist; bucket `products` existence is data-level (dashboard). M8 adds public-read/admin-write policies. |
| Secure RPC | ✅ | `place_order` is `SECURITY DEFINER` + `search_path` pinned + caller check (`auth.uid()` vs `p_user_id`). |

**Remaining security risks after reconciliation:**
- Storage: until M8 + bucket verification, image storage is either inaccessible or (if a
  public bucket exists) potentially world-writable — **verify in dashboard**.
- Auth config (password policy, email confirmation, captcha) is **outside schema** and
  unverified — must be set in the dashboard.
- `anon`/`authenticated` broad table grants remain (mitigated by RLS).

---

## Manual steps (in order)

> Perform on **staging first** if one exists; otherwise schedule a maintenance window.

1. **Back up** (mandatory, before anything):
   `supabase db dump --linked -f backups/pre_reconciliation_$(date +%Y%m%d_%H%M).sql`
   Also trigger a dashboard backup/PITR snapshot.
2. **Capture baseline:** `supabase db pull` → review generated `<ts>_remote_schema.sql`.
3. **Verify preconditions (read-only queries in SQL Editor):**
   - `SELECT id, count(*) FROM public.products GROUP BY id HAVING count(*) > 1;` (must be empty before PK change / M7)
   - `SELECT user_id, product_id, count(*) FROM public.cart_items GROUP BY 1,2 HAVING count(*)>1;` (dedupe before UNIQUE / M5)
   - `SELECT id, name, public FROM storage.buckets;` (confirm `products` bucket + visibility)
   - `SELECT DISTINCT role FROM public.profiles;` (see values to normalize)
4. **Apply the immediate Critical fix (M3, live-compatible)** — SQL is in
   `Phase1_Final_Closure_Report.md` (Manual Steps §1). Small, additive, safe.
5. **Author + apply migrations M1→M8** per `Migration_Strategy.md`, each with its paired
   frontend change, validating (`db diff`) after each.
6. **Dashboard verifications:** Storage bucket/policies (M8), Auth settings (password/
   confirmation/captcha).

## Required backups
- Pre-reconciliation full dump (step 1) + dashboard PITR snapshot.
- A fresh dump immediately before **M6** (normalization) and **M7** (structural) — the only
  steps not reversible by a simple `DROP`.

## Commands to run (reference)
```bash
# read-only verification
supabase migration list --linked          # expect Remote column empty pre-reconciliation
supabase db diff --linked                 # expect large drift now; "no changes" when done
supabase db dump --linked -s public -f /tmp/public.sql
supabase db dump --linked -s storage -f /tmp/storage.sql

# reconciliation (per migration)
supabase migration new <slug>             # author SQL into the generated file
supabase db push                          # apply pending migrations to linked project
```

## Expected outputs
- `migration list` **before:** local `001/002/003/<ts>` with **empty Remote** column.
- `migration list` **after M0+push:** baseline + reconciliation migrations shown as applied
  on both Local and Remote.
- `db diff` **after full reconciliation:** *"No schema changes found"*.
- Smoke: signup creates a `profiles` row (trigger); browse→cart→checkout creates an order
  via `place_order`; admin can update order status and upload a product image.

## Validation steps
- After each migration: `supabase db diff --linked` trends toward empty.
- App smoke test (see `Frontend_Database_Compatibility.md` checklist) per area shipped.
- RLS spot-checks (as a normal user): cannot set own `role`; cannot read others' orders;
  cannot insert `order_items` directly.
- CI (`npm ci && lint && test && build`) stays green after each paired frontend change.

## Rollback plan
- **Additive migrations (M1, M2, M4, M5, M8):** reverse with `DROP COLUMN/POLICY/FUNCTION/
  TRIGGER/INDEX/CONSTRAINT` — no data loss.
- **M3 (policy):** restore the previous `USING`-only policy definition.
- **M6 (normalization) / M7 (structural):** **restore from the pre-step backup** (dump
  restore or dashboard PITR). These are the high-risk, window-only steps.
- If checkout regresses after M4: the previous state had no working RPC either, so revert
  `place_order` and investigate on staging (do not leave prod half-migrated).

---

## Readiness checklist

| Item | Ready? |
|---|---|
| Schema comparison complete | ✅ |
| Canonical proposal complete | ✅ |
| Frontend compatibility mapped | ✅ |
| Migration strategy (named, deps, rollback, risk) | ✅ |
| ADR recorded | ✅ |
| Destructive steps identified + gated | ✅ |
| Backup + preconditions defined | ✅ |
| Live actions require human execution | ⏳ (backup, `db pull`, data verifications) |
| Storage bucket / auth settings | ❓ dashboard-only (documented) |

**Verdict:** Phase 1.5 **planning is COMPLETE**. Execution is **ready to begin** once a human
performs the backup, `db pull`, and the four verification queries. No assumptions were made
where evidence was missing (storage buckets, auth config, row-level data) — those are
explicitly flagged for manual verification.

## Required approvals (before execution)

| # | Item | Approver | Why approval is needed |
|---|---|---|---|
| 1 | Adopt live as source of truth (ADR-001) | Project owner | Sets the whole reconciliation direction |
| 2 | Take/verify a production backup before M6/M7 | Owner / DBA | Data-safety gate for non-reversible steps |
| 3 | `products` PK `(id,name)` → `(id)` (M7) | Owner / DBA | Destructive-class; needs dedupe + window |
| 4 | Rename `products."Description"`→`description` (M7) | Owner | Column rename (copy-then-drop) |
| 5 | `profiles.role` normalization + CHECK (M6) | Owner | Data mutation across users |
| 6 | UNIQUE constraints on `cart_items`/`wishlists` (M5) | Owner | Requires dedupe of existing rows |
| 7 | Create vs disable `payments`/`pickup_locations`/`addresses` | Product owner | Feature-scope decision (deferred by default) |
| 8 | Optional table renames (Path B) | Owner | Only if code-adaptation path is rejected |

Additive, non-destructive steps (M1, M2, M3, M4, M8) do **not** require special approval
beyond the go-ahead to begin, but still run on staging first + with a backup.

## Phase 2 blockers

Phase 2 (Core Commerce Completion) **cannot start** until these are cleared:

1. **DB drift** — live schema reconciled to canonical (M0–M5 at minimum).
2. **Checkout** — `place_order()` created on live (M4); `order_items` writes flow through it.
3. **Cart/Wishlist** — table-name code fix + owner RLS policies (M2) so they aren't deny-all.
4. **Critical security** — role-escalation fix applied on live (M3).
5. **Products model** — `stock`/`discount_price`/image fields present (M1); category model chosen.
6. **Storage** — `products` bucket verified + policies (M8) for admin image upload.

Non-blocking but recommended before Phase 2: service-layer/RLS tests, layout bug fix (F-05).

## Go / No-Go recommendation

**Recommendation: GO for planning-to-execution hand-off; NO-GO for unattended/automated
execution.**

- **GO:** the analysis package is complete and internally consistent; a human engineer has
  everything needed to execute safely on staging.
- **NO-GO (automated):** execution depends on a backup, `db pull`, four data-level
  verification queries, and several approvals (above) — none of which may be guessed or
  auto-applied under the current rules. Begin only after Required Approvals #1–#2 and the
  §3 verification queries.

## Engineering score (Phase 1.5 documentation package)

| Category | Score | Justification |
|---|---:|---|
| Evidence quality | 9/10 | Live `public`+`storage` dumps + full frontend read; only data-level items unverifiable by design |
| Comparison completeness | 9/10 | All object classes covered incl. FKs, RLS, functions, storage |
| Canonical proposal soundness | 8/10 | Additive-first, evidence-bound; a few decisions correctly deferred to owner |
| Migration strategy | 8/10 | Sequenced with deps/rollback/risk; no fabrication |
| Risk management | 9/10 | Destructive steps gated, backups + rollback per step |
| Readiness for hand-off | 9/10 | Clear manual steps, approvals, validation, Go/No-Go |
| **Overall (Phase 1.5 docs)** | **8.5/10** | Complete, review-ready package; execution intentionally left to humans |

## What could not be verified (and how to verify)
- **Storage bucket `products` existence/visibility** → `SELECT id, name, public FROM storage.buckets;` or dashboard.
- **Auth configuration** (password policy, email confirmation, captcha) → Supabase dashboard → Authentication → Providers/Policies.
- **`products.id` uniqueness / cart dupes** → the verification queries in Manual Steps §3.
- **Row counts / data volume** (affects window sizing) → `SELECT count(*)` per table.
