# Database Reconciliation — Master Operational Runbook

**Status:** Operational guide for executing the live-DB ↔ repo ↔ frontend reconciliation.
**Date:** 2026-07-12
**Owner on execution:** engineer with Supabase project access (`qfcygrxrfszcdltangec`) + repo write.
**Source of truth (do not re-derive):** `Final_Canonical_Schema.md`,
`Reconciliation_Decision_Log.md`, `Migration_Strategy.md`, `ADR-001-Database-Reconciliation.md`,
`Baseline_Migration_Verification.md`, `Frontend_Database_Compatibility.md`,
`Schema_Comparison_Matrix.md`, `Phase1_5_Readiness_Report.md`.

> This runbook is **planning only**. It contains **no SQL and no migrations**. Where a
> migration is referenced it points to the named plan `M0..M8` in `Migration_Strategy.md`,
> which the executing engineer authors with `supabase migration new` at execution time.
> Read-only validation checks are referenced from `Phase1_5_Readiness_Report.md` (§Manual
> Steps) rather than restated as SQL.

---

## 0. Prerequisites

**Access & tools**
- Supabase CLI (≥ 2.106) authenticated (`supabase projects list` succeeds).
- Linked project confirmed (`supabase/.temp/project-ref` = `qfcygrxrfszcdltangec`).
- Docker running (needed by `supabase db diff`).
- Repo write access + CI green on `main` (`npm ci && lint && test && build`).
- A **staging** Supabase project (strongly recommended) OR an approved maintenance window on prod.

**Approvals obtained (see Readiness §Required Approvals)**
- ADR-001 direction (adopt live as source of truth) approved.
- Sign-off for destructive/normalizing steps (M6, M7) and feature-scope of `payments`/`pickup_locations`/`addresses`.

**Backups**
- Fresh full dump before starting and again immediately before M6 and M7:
  `supabase db dump --linked -f backups/pre_<stage>_<ts>.sql` + dashboard PITR snapshot.

---

## 1. Workstream A — Execution sequence (Current State → Production verification)

Ordered stages. Each has: **objective · prerequisites · expected result · verification · rollback trigger.**

### Stage 0 — Current state confirmation
- **Objective:** confirm reality matches the documented baseline before any change.
- **Prerequisites:** §0 met.
- **Expected result:** `supabase migration list --linked` shows Remote column empty; `db diff` shows large drift.
- **Verification:** outputs match `Baseline_Migration_Verification.md`.
- **Rollback trigger:** if live schema differs from the documented baseline → STOP, re-run Workstream A (Phase 1.6 A) to refresh the baseline before proceeding.

### Stage 1 — Backups
- **Objective:** guarantee recoverability.
- **Prerequisites:** Stage 0 passed.
- **Expected result:** dump file saved + PITR snapshot timestamp recorded.
- **Verification:** dump file non-empty; snapshot visible in dashboard.
- **Rollback trigger:** backup fails/incomplete → do not proceed.

### Stage 2 — Baseline adoption (M0)
- **Objective:** put a real baseline under version control.
- **Prerequisites:** backup done.
- **Expected result:** `docs/database/generated_baseline/001_initial_schema.sql` promoted into `supabase/migrations/` as the initial migration; fictional `001_schema_rls_place_order.sql` retired; empty `20260617042152_remote_schema.sql` removed; remote migration history repaired to mark the baseline as applied.
- **Verification:** `supabase migration list --linked` shows the baseline as applied on Remote; `supabase db diff --linked` returns *"No schema changes found"* (baseline == live).
- **Rollback trigger:** `db diff` shows unexpected differences after adoption → revert migration-history repair (see Rollback §F), restore file state.

### Stage 3 — Migration creation (author M1→M8 plans as files)
- **Objective:** author forward migrations per `Migration_Strategy.md` (no application yet).
- **Prerequisites:** baseline adopted and diff-clean.
- **Expected result:** migration files exist locally, reviewed, not pushed.
- **Verification:** peer review; `supabase db diff` unchanged (authoring doesn't apply).
- **Rollback trigger:** review rejects a migration → revise before applying.

### Stage 4 — Migration validation (staging)
- **Objective:** apply migrations on staging (or a `db branch`) and confirm.
- **Prerequisites:** staging available; migrations authored.
- **Expected result:** each migration applies cleanly; `db diff` trends to empty.
- **Verification:** per-migration validation (Workstream B table) passes; RLS spot-checks pass.
- **Rollback trigger:** any migration errors or a validation query fails → halt, fix on staging.

### Stage 5 — Frontend updates (paired, on a branch)
- **Objective:** align frontend to canonical schema (see Workstream D).
- **Prerequisites:** corresponding DB migration validated on staging.
- **Expected result:** branch builds; unit tests pass; affected flows work against staging.
- **Verification:** `npm ci && lint && test && build` green; manual smoke on staging.
- **Rollback trigger:** build/test failure or broken flow → revert branch commit(s).

### Stage 6 — Testing (integration on staging)
- **Objective:** end-to-end validation of the paired DB+frontend change.
- **Prerequisites:** Stage 5 deployed to staging.
- **Expected result:** signup→profile, browse→cart→checkout, admin order update, image upload all succeed.
- **Verification:** Verification Checklist (Workstream E) passes on staging.
- **Rollback trigger:** any Critical checklist item fails → do not promote to prod.

### Stage 7 — Deployment (production)
- **Objective:** apply the validated change to prod in the correct order.
- **Prerequisites:** Stage 6 green; fresh prod backup; window if M6/M7.
- **Expected result:** `supabase db push` applies pending migration; frontend deployed after.
- **Verification:** `db diff --linked` clean; app loads; smoke test on prod.
- **Rollback trigger:** migration error, `db diff` unexpected, or prod smoke failure → execute Rollback §F for that stage.

### Stage 8 — Production verification
- **Objective:** confirm the system is healthy post-deploy.
- **Prerequisites:** Stage 7 done.
- **Expected result:** all Workstream E items pass on prod; error logs clean.
- **Verification:** monitored for an agreed soak period.
- **Rollback trigger:** elevated error rate / broken core flow within soak → roll back.

---

## 2. Workstream B — Migration runbook (per planned migration)

Migrations are the `M0..M8` plans from `Migration_Strategy.md`. Deployment order:
**M0 → M1 → M3 → M2 → M4 → M5 → M8 → M6 → M7** (M3 pulled early to close the Critical security gap; M6/M7 last, window-gated).

| Mig | Purpose | Depends on | Manual steps | Validation (read-only) | Expected result | Rollback | Risk | Time |
|---|---|---|---|---|---|---|---|---|
| **M0** Baseline | Adopt live baseline | Backup | Promote baseline file; retire fictional 001; `migration repair` | `migration list`, `db diff` clean | Baseline == live | Undo repair + restore files | Low | 0.5–1 h |
| **M1** Additive columns | Add `profiles.full_name/updated_at`, `orders.payment_status/note/updated_at`, `products.stock/discount_price/image_url/images`, `order_items.image_url/created_at` | M0 | author + push | `db diff` clean; columns present | New columns, defaults backfilled | `DROP COLUMN` (new only) | Low | 0.5 h |
| **M3** Critical security | profiles UPDATE `WITH CHECK` + admin policy | M0 (M4 for admin variant) | author + push | RLS spot-check: user cannot change own `role` | Role escalation blocked | Restore prior USING-only policy | Low | 0.25 h |
| **M2** RLS policies | Owner policies for `cart_items`/`wishlists`; public/admin for `categories`/`products` | M4 (`is_admin`) | author + push | Spot-check reads/writes as user/admin | Deny-all tables usable + secure | `DROP POLICY` | Low–Med | 0.5 h |
| **M4** Functions/triggers | `is_admin`, `handle_new_user`+trigger, `place_order`, `set_updated_at` | M1 | author + push; test signup + checkout on staging | Signup creates profile; checkout via RPC works | Server logic present | `DROP FUNCTION/TRIGGER` | Med | 1 h |
| **M5** FK/UNIQUE/CHECK/index | Integrity + performance | M1, M7 for product FKs; **dedupe first** | run dedupe check (Readiness §Manual Steps); author + push | Constraints/indexes present; no violation errors | Referential integrity | drop constraints/indexes | Med | 0.5–1 h |
| **M8** Storage | `products` bucket policies (public read/admin write) | M4; bucket verified | verify bucket in dashboard; author + push; fix client `getPublicUrl` | Admin upload works; public read of images | Secure storage | drop storage policies | Med | 0.5 h |
| **M6** Normalization | Backfill `full_name`; normalize `role`; backfill `category_id`; VALIDATE CHECKs | M1; **backup + approval + window** | backup; run backfills; VALIDATE | Values conform; CHECKs validated | Clean data | **Restore from backup** | Med–High | 1–2 h |
| **M7** Structural | products PK `(id,name)`→`(id)`; rename `"Description"`→`description`; (optional table renames) | all prior; **backup + approval + window** | verify id uniqueness; backup; apply | PK single-col; column renamed | Normalized structure | **Restore from backup** | High | 1–2 h |

**Validation query references:** the read-only checks (id uniqueness, cart/wishlist duplicates, storage bucket, distinct roles) are defined in `Phase1_5_Readiness_Report.md` → "Manual steps §3". No SQL is authored in this runbook.

---

## 3. Workstream C — Deployment strategy

Pipeline: **Development → Local verification → Staging → Staging validation → Production backup → Production migration → Application deployment → Post-deployment verification.**

1. **Development:** author migration + paired frontend change on a feature branch.
2. **Local verification:** `npm ci && lint && test && build`; optionally `supabase start` local stack to apply the migration to a local DB.
3. **Staging:** `supabase db push` to staging (or `supabase db branch`), deploy frontend build to a staging URL.
4. **Staging validation:** full Verification Checklist (Workstream E) on staging.
5. **Production backup:** `supabase db dump` + PITR snapshot (mandatory before push).
6. **Production migration:** `supabase db push` (single migration group at a time, in order).
7. **Application deployment:** deploy the paired frontend build **after** the DB migration succeeds.
8. **Post-deployment verification:** Workstream E on prod + log/error monitoring for the soak period.

**Downtime / zero-downtime**
- **M0–M5, M8:** expected **zero downtime** — additive and online. Create indexes with `CONCURRENTLY` (outside a transaction) to avoid table locks.
- **M6 (normalization):** online but run in low-traffic window; brief write contention possible.
- **M7 (PK change / column rename):** may take a short lock on `products`; schedule a **maintenance window** (expected minutes, sized by row count — see Unknowns).
- Because reconciliation is DB-additive-first, the **old frontend keeps working** throughout (it only reads columns that still exist); broken areas (cart/wishlist/checkout) are already broken today, so their fixes are strictly improvements.

---

## 4. Workstream D — Frontend rollout plan

Principle: **DB migration first (additive, backward-compatible), then the paired frontend change.** No table/column renames on live, so no backward-compatibility break from the DB side.

| Area | File(s) | Depends on DB | Deploy order | Backward compatible? | Rollback |
|---|---|---|---|---|---|
| Cart service | `services/cartService.js` (`cart`→`cart_items`; fix `this.*`) | M2 (owner RLS) | after M2 | Yes (today broken; fix only improves) | revert file |
| Cart context | `context/CartContext.jsx` | via cartService | with cart service | Yes | revert |
| Wishlist service + context | `services/wishlistService.js`, `context/WishlistContext.jsx` (`wishlist`→`wishlists`, realtime table) | M2 | after M2 | Yes | revert |
| Order service | `services/orderService.js` (`total_amount`→`total`; RPC exists) | M1, M4 | after M4 | Yes | revert |
| Admin service | `services/adminService.js` (new order cols; `stock`; `getPublicUrl` fix) | M1, M4, M8 | after M8 | Yes | revert |
| Product service | `services/productService.js` (category model; snake_case fields) | M1, M6 (category_id backfill) | after M6 | Yes | revert |
| Auth context | `context/AuthContext.jsx` (`full_name` write; role display) | M1 | after M1 | Yes | revert |
| Constants | `utils/constants.js` (`ROLES` `user`→`customer`) | M6 (role normalize) | with M6 | Yes | revert |
| Customer pages | `Cart.jsx`, `Wishlist.jsx`, `Checkout.jsx`, `ProductDetail.jsx`, `Orders*.jsx` | via services/contexts | after their service | Yes | revert |
| Admin pages | `AdminProducts*`, `AdminOrders*`, `AdminInventory`, `AdminUsers` | via adminService | after adminService | Yes | revert |
| Deferred/guarded | `paymentService.js`, `userService` address methods, `AdminPickupLocations.jsx` | Phase 2 tables | guard/disable now | N/A | re-enable when tables exist |

**Routes:** no route changes required for reconciliation (the dead duplicate `/` route was
already removed in Phase 1). Guarded admin pages remain routed but should show a
"coming soon"/disabled state until their tables exist.

---

## 5. Workstream E — Verification checklist (pass/fail)

### Database
- [ ] **Tables:** all 7 canonical tables present; names match `Final_Canonical_Schema.md`. *(Pass: `db diff` clean.)*
- [ ] **Constraints:** FKs, `UNIQUE(user_id,product_id)`, `CHECK(quantity>0)`, role/status/payment CHECKs exist. *(Pass: present + validated, no violation errors.)*
- [ ] **Indexes:** required indexes exist (orders, order_items, cart_items, products, FTS). *(Pass: listed in schema.)*
- [ ] **RLS:** every table has intended policies; `cart_items`/`wishlists`/`categories` no longer deny-all; `order_items` INSERT blocked. *(Pass: spot-checks behave.)*
- [ ] **RPCs:** `is_admin`, `handle_new_user`, `place_order` exist and execute. *(Pass: checkout + signup succeed.)*
- [ ] **Triggers:** `on_auth_user_created`, `set_updated_at` fire. *(Pass: profile auto-created; `updated_at` changes on update.)*

### Frontend
- [ ] **Authentication:** signup creates a `profiles` row; login; role reflected. *(Pass.)*
- [ ] **Cart:** add/update/remove/clear against `cart_items`; totals correct. *(Pass.)*
- [ ] **Wishlist:** toggle persists against `wishlists`; realtime updates. *(Pass.)*
- [ ] **Checkout:** `place_order` creates order+items, decrements stock, clears cart. *(Pass.)*
- [ ] **Orders:** customer sees own orders; statuses render. *(Pass.)*
- [ ] **Admin:** order status update; product CRUD; inventory low-stock. *(Pass.)*
- [ ] **Storage uploads:** admin uploads product image; public URL resolves. *(Pass.)*
- [ ] **Guarded features:** payments/addresses/pickup show disabled state, no crash. *(Pass.)*

### Infrastructure
- [ ] **CI:** `.github/workflows/ci.yml` green on the PR. *(Pass: all stages green.)*
- [ ] **Build:** `npm run build` succeeds. *(Pass.)*
- [ ] **Tests:** `npm test` green (unit/smoke). *(Pass: 18+.)*
- [ ] **Env vars:** `VITE_SUPABASE_URL`/`ANON_KEY` set per environment; no service-role key in client. *(Pass.)*
- [ ] **Migration state:** `supabase db diff --linked` → no changes; `migration list` aligned. *(Pass.)*

---

## 6. Workstream F — Rollback runbook (per stage)

| Stage | Failure scenario | Decision point | Recovery / DB rollback | App rollback | Data recovery | Manual verification | Comms |
|---|---|---|---|---|---|---|---|
| Backup | Backup incomplete | before any change | re-run backup; do not proceed | n/a | n/a | dump non-empty | notify owner |
| M0 baseline | `db diff` not clean after adoption | post-adoption | undo `migration repair`; restore file state | n/a | none (read-only) | `db diff` re-run | note in log |
| M1 additive | push error | on push failure | `DROP COLUMN` for added cols | keep old frontend | none | `db diff` | — |
| M3 security | policy breaks legit update | staging test | restore prior USING-only policy | none | none | RLS spot-check | flag security owner |
| M2 RLS | users lose access | staging test | `DROP POLICY`/restore | none | none | read/write as user | — |
| M4 functions | checkout fails on staging | staging test | `DROP FUNCTION/TRIGGER`; revert to pre-M4 | keep old frontend (no RPC calls) | none | signup+checkout | — |
| M5 constraints | constraint add fails (dirty data) | on error | drop constraint; run dedupe; retry | none | dedupe rows | violation query empty | — |
| M8 storage | uploads/public read broken | staging test | drop storage policies; revert client fix | revert adminService | none | upload+fetch image | — |
| M6 normalization | data corrupted/CHECK fails | **hard decision point** | **restore from pre-M6 backup (PITR)** | revert constants/frontend | restore backup | row samples correct | notify owner; window |
| M7 structural | PK change/rename fails or locks too long | **hard decision point** | **restore from pre-M7 backup (PITR)** | revert product frontend | restore backup | product reads OK | notify owner; window |
| Prod deploy | elevated errors post-deploy | within soak | roll back last migration (or restore) + redeploy prior frontend build | redeploy previous build | per step above | Workstream E core items | status update |

**Golden rules:** never leave prod half-migrated; additive steps reverse with `DROP`; M6/M7
reverse **only** via backup restore; always roll back the frontend to the build that matches
the current DB state.

---

## 7. Troubleshooting

- **`db diff` shows drift after a clean push:** local migrations out of order or a manual
  dashboard change occurred → re-pull, compare, re-author.
- **`migration list` Remote empty after M0:** `migration repair --status applied <version>` was
  not run for the baseline → run it (this writes only to the migration-history table).
- **Checkout errors "function place_order does not exist":** M4 not applied to that
  environment → apply M4 before deploying the order frontend.
- **Cart/wishlist empty or 403:** M2 owner policies missing, or frontend still points at
  `cart`/`wishlist` → verify M2 applied + frontend renamed to `cart_items`/`wishlists`.
- **Constraint add fails:** dirty/duplicate data → run the dedupe/uniqueness checks
  (Readiness §Manual Steps) before M5/M7.
- **Image upload returns undefined URL:** client still uses `publicURL` → apply the
  `getPublicUrl` fix (paired with M8).
- **Docker error on `db diff`:** Docker not running → start Docker (only `db diff` needs it).

---

## 8. Post-deployment verification
- Run the full Workstream E checklist on production.
- Monitor Supabase logs + app error tracking for the agreed soak (suggest ≥ 24 h for M6/M7).
- Confirm `supabase db diff --linked` remains clean.
- Record applied migration versions and backup references in the change log.

---

## 9. Sign-off checklist
- [ ] Backups taken (start, pre-M6, pre-M7) and locations recorded.
- [ ] Baseline adopted; `db diff` clean.
- [ ] Each migration validated on staging before prod.
- [ ] Critical security (M3) applied and verified.
- [ ] All Workstream E items pass on prod.
- [ ] Frontend build deployed matches DB state.
- [ ] CI green on the merged PR.
- [ ] Rollback plan reviewed; approver sign-off for M6/M7.
- [ ] Change log updated; ADR-001 status moved to "Accepted/Executed".

---

## 10. Traceability (decision → step → validation → rollback → trigger)
Each `Reconciliation_Decision_Log.md` decision maps to a migration (`M0..M8`) and/or a
frontend rollout row (§4), which has a validation item (§5) and a rollback row (§6) with a
defined trigger (§1 stage triggers). See `Phase1_6_Execution_Readiness.md` "Final Validation"
for the explicit coverage assertion and remaining manual actions.
