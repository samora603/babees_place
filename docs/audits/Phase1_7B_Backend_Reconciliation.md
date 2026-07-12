# Phase 1.7B — Workstream 3: Backend Reconciliation & Production Readiness

**Date:** 2026-07-12
**Branch:** `phase-1.7-reconciliation`
**Type:** Read-only repository validation. **No** DB connection, **no** `db push`, **no**
migration execution/repair, **no** production change, **no** commit/branch/tag.
**Authoritative specs:** `Final_Canonical_Schema.md`, `Reconciliation_Decision_Log.md`,
`Migration_Strategy.md`, `Migration_History.md`, `Database_Reconciliation_Runbook.md`,
`Frontend_Database_Compatibility.md`, `Phase1_7B_Frontend_Reconciliation.md`,
`Phase1_7B_Migration_Authoring_Report.md`, `Phase1_7B_Migration_Review.md`.

---

## 1. Executive summary

The repository backend is a single, coherent, **forward-only** migration chain
`001 → 010` on top of a faithful live baseline, plus `supabase/config.toml`. Static
validation confirms the chain is **internally consistent, correctly ordered, free of
circular dependencies, idempotent (except the baseline by design), transaction-wrapped,
and aligned with the approved canonical schema and decision log.** Server logic is
sound: `place_order()` is server-authoritative (locks stock, computes totals server-side,
enforces authorization), the profile role-escalation hole is closed with a `WITH CHECK`,
RLS covers every table, and storage writes are admin-gated.

The backend is **repository-ready** for the documented staging/production rollout. It is
**not** yet self-applying: three classes of work remain and are all **manual by design** —
(a) the mandatory `migration repair` to adopt the baseline on the empty live history,
(b) approvals + backup + `VALIDATE`/legacy-data reconciliation for the two gated
migrations (`007`, `008`), and (c) production auth/config hardening (site URL, SMTP,
password policy). Two documentation artifacts have drifted (`Migration_History.md` still
says "no forward migrations authored"; the file-naming convention differs from what that
doc prescribes) and there is no `seed.sql` although `config.toml` references one.

**Overall engineering score: 9.2 / 10. Production Readiness: 8.6 / 10.
Recommendation: GO for staging; CONDITIONAL GO for production** (pending the gated-migration
approvals, backup, and post-migrate `VALIDATE` steps enumerated in §12).

---

## 2. Stage 1 — Backend inventory

### 2.1 Files

| Area | Artifact | Notes |
|---|---|---|
| Migrations (active) | `001`–`010` in `supabase/migrations/` | 001 = baseline pg_dump; 002–010 forward |
| Migrations (archived) | `archive/001_schema_rls_place_order.sql`, `archive/002_phase1_security_hardening.sql`, `archive/003_phase1_indexes_constraints.sql` | fictional/superseded; **never apply** |
| Config | `supabase/config.toml` | api/db/auth/storage/realtime/edge settings |
| Seed | *(none)* | `config.toml` `db.seed` references `./seed.sql` — **file absent** |
| Edge Functions | *(none)* | `edge_runtime.enabled=true` but no `functions/` dir |
| Views | *(none)* | no views defined or required by canonical |

### 2.2 Database objects introduced by the chain

| Object type | Objects | Migration |
|---|---|---|
| Tables (baseline) | `profiles`, `products`, `categories`, `cart_items`, `wishlists`, `orders`, `order_items` | 001 |
| Enum | `public.order_status` (created 001, **dropped** 008 — unused) | 001 / 008 |
| Functions | `is_admin()`, `handle_new_user()`, `set_updated_at()`, `place_order(uuid)` | 003 |
| Triggers | `on_auth_user_created` (auth.users AFTER INSERT); `set_{profiles,products,orders}_updated_at` (BEFORE UPDATE) | 003 |
| RLS policies (table) | baseline 10; replaced/added in 004 (profiles ×4, cart_items, wishlists, categories ×2, products, order_items) | 001 / 004 |
| Storage | bucket `products` (public) + 4 `storage.objects` policies | 006 |
| FKs | order_items→orders (001, baseline); profiles→auth.users (001); user_id→auth.users ×3 (005 NOT VALID); product_id ×3 (009 NOT VALID); category_id→categories (009 VALIDATE) | 001/005/009 |
| Constraints | quantity CHECKs (005); role/status/payment_status CHECKs (007); (user_id,product_id) UNIQUE ×2 (009); products PK (id) (008) | 005/007/008/009 |
| Indexes | 11 (orders ×3, order_items ×2, cart/wishlist product_id, products category_id/is_active/slug, FTS GIN) | 010 |
| RPC (client-callable) | `place_order` (authenticated only) | 003 |

### 2.3 Config summary

- **API:** `public`+`graphql_public` exposed; `max_rows=1000`; `auto_expose_new_tables`
  commented (secure default — new entities not auto-exposed).
- **DB:** Postgres major 17; migrations enabled; seed enabled → `./seed.sql`.
- **Auth:** email signup on; **email confirmations OFF**; OAuth providers all disabled
  (future-ready); MFA/OTP/passkey scaffolding present but disabled; `minimum_password_length=6`;
  `site_url=http://127.0.0.1:3000` (dev).
- **Storage:** enabled; 50 MiB limit; S3 protocol on.
- **Realtime:** enabled (used by `WishlistContext`).

---

## 3. Stage 2 — Migration validation

### 3.1 Dependency map (no cycles)

```
001 baseline (tables, enum, PKs, 2 FKs, RLS enable, 10 policies, grants)
 └─ 002 additive columns ............ needs 001
     └─ 003 functions + triggers .... needs 002 (new columns)
         ├─ 004 RLS + role fix ...... needs 003 (is_admin)
         ├─ 006 storage policies .... needs 003 (is_admin)
         └─ 005 defaults/user-FK/CHK  needs 002 (ordered)
             └─ 007 data normalize 🛑 needs 002,005
                 └─ 008 PK/rename/enum🛑 needs 007
                     ├─ 009 product FK/UNIQUE  needs 007,008
                     └─ 010 indexes + FTS ..... needs 002,008 (description)
```

Linear apply order `001→002→…→010` satisfies every edge. **No circular dependencies.**
🛑 = approval-gated, data-/structure-mutating.

### 3.2 Per-migration checklist

| Mig | Purpose | Idempotent | Txn | Forward-only | Rollback notes | Verdict |
|---|---|---|---|---|---|---|
| 001 | Baseline snapshot | ⚠️ No (raw dump: bare `CREATE TYPE`/`CREATE POLICY`) — **by design, adopt via repair, never re-run** | n/a | yes | via repair/restore | ✅ (adopt-only) |
| 002 | Additive columns | ✅ `ADD COLUMN IF NOT EXISTS` | ✅ | yes | DROP COLUMN list | ✅ |
| 003 | Functions/triggers | ✅ `CREATE OR REPLACE` + `DROP TRIGGER IF EXISTS` | ✅ | yes | DROP fn/trg | ✅ |
| 004 | RLS + role fix | ✅ `DROP POLICY IF EXISTS` before create | ✅ | yes | recreate prior policies | ✅ |
| 005 | Defaults/FK/CHECK | ✅ DROP DEFAULT no-op; `DROP CONSTRAINT IF EXISTS` | ✅ | yes | DROP CONSTRAINT | ✅ |
| 006 | Storage policies | ✅ `ON CONFLICT DO NOTHING`; DROP POLICY IF EXISTS | ✅ | yes | DROP policies | ✅ |
| 007 🛑 | Data normalize | ✅ WHERE-guarded updates; DROP CONSTRAINT IF EXISTS | ✅ | yes | **restore from backup** | ✅ (gated) |
| 008 🛑 | PK/rename/enum drop | ✅ catalog-guarded `DO` blocks | ✅ | yes | **restore from backup** | ✅ (gated) |
| 009 | Product FK/UNIQUE | ✅ DROP CONSTRAINT IF EXISTS | ✅ | yes | DROP CONSTRAINT | ✅ |
| 010 | Indexes + FTS | ✅ `CREATE INDEX IF NOT EXISTS` | ✅ (+ documented CONCURRENTLY variant) | yes | DROP INDEX | ✅ |

**Naming:** consistent `NNN_snake_case.sql`; each header documents purpose, deps, risk,
rollback, expected changes, idempotency. **Data preservation:** additive/constraint steps
never touch stored rows; only `007` mutates data (gated, backup-first).

### 3.3 Findings

- **F-1 (Info, by design):** `001` is not idempotent (bare `CREATE TYPE`/`CREATE POLICY`).
  Because live history is empty, it must be adopted with
  `supabase migration repair --status applied 001` (mark applied **without** running);
  re-running against live would fail on duplicate type/policies. Correctly documented.
- **F-2 (Low):** `010`'s transactional `CREATE INDEX` briefly locks writes; a
  `CONCURRENTLY` variant is provided for large tables (must run outside a txn). Acceptable
  at MVP scale.

---

## 4. Stage 3 — RPC / function review

### 4.1 `place_order(p_user_id uuid DEFAULT auth.uid())`
- **SECURITY DEFINER**, `SET search_path = public`; all objects schema-qualified;
  `auth.uid()` explicitly `auth`-qualified → search-path safe. ✅
- **AuthZ:** rejects null user; requires `auth.uid() = p_user_id OR is_admin()`. ✅
- **Correctness:** `FOR UPDATE OF p` locks product rows (TOCTOU-safe); validates stock;
  **server-computed** total (`COALESCE(discount_price, price)`), never trusts client;
  snapshots name/price/image into `order_items`; decrements stock; clears cart; all in
  one transaction. ✅
- **Grants:** `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated`. ✅
- **R-1 (Low–Medium):** the stock-decrement `UPDATE products … FROM cart_items` assumes
  **at most one cart row per (user, product)**. That invariant is guaranteed only after the
  `009` UNIQUE (and `007` dedupe). In the phased rollout, checkout is enabled at `003`/`004`
  (before `009`). Duplicate cart rows would cause `UPDATE … FROM` to subtract only one
  matching row's quantity (potential oversell) and emit duplicate line items. **Mitigation
  in place:** `cartService.addToCart` merges quantities app-side, and `007` dedupes existing
  rows. **Recommendation:** either (a) apply the `cart_items` UNIQUE before enabling
  checkout, or (b) make `place_order` aggregate the cart by `product_id` (`GROUP BY`) so it
  is correct regardless of duplicates (defense-in-depth).

### 4.2 `is_admin()`
- SQL, **STABLE, SECURITY DEFINER**, `search_path=public`. Filters `id = auth.uid()` →
  cannot read other rows; used by RLS to avoid profiles-policy recursion. ✅
- **R-2 (Low, least-privilege):** baseline `ALTER DEFAULT PRIVILEGES` grants `EXECUTE` on
  new functions to `anon`/`authenticated`/`PUBLIC`. `is_admin()` is harmless to anon
  (returns false) but should be locked down. **Recommendation:** add to `003`
  `REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;`.

### 4.3 `handle_new_user()`
- **SECURITY DEFINER** (needs to insert into `profiles` bypassing RLS on signup),
  `search_path=public`; `ON CONFLICT (id) DO NOTHING`; assigns canonical role `'customer'`;
  reads `full_name`/`phone` from `raw_user_meta_data`. ✅
- **R-3 (Low):** same anon-EXECUTE default-privilege note as R-2 (calling it outside a
  trigger context errors, so not exploitable). Optional revoke.

### 4.4 `set_updated_at()`
- Plain `plpgsql` trigger fn (no DEFINER needed). Sets `NEW.updated_at = now()`. ✅
- **R-4 (Low, hygiene):** no explicit `SET search_path`; body references no schema objects
  (only `NEW`), so safe, but pinning `search_path=public` would match the others.

---

## 5. Stage 4 — Trigger review

| Trigger | Table | Timing | Fn | Assessment |
|---|---|---|---|---|
| `on_auth_user_created` | `auth.users` | AFTER INSERT / ROW | `handle_new_user` | ✅ correct place to provision profile; idempotent via `ON CONFLICT` |
| `set_profiles_updated_at` | `public.profiles` | BEFORE UPDATE / ROW | `set_updated_at` | ✅ |
| `set_products_updated_at` | `public.products` | BEFORE UPDATE / ROW | `set_updated_at` | ✅ |
| `set_orders_updated_at` | `public.orders` | BEFORE UPDATE / ROW | `set_updated_at` | ✅ (client-sent `updated_at` correctly overridden; WS2 removed the manual set) |

- All created with `DROP TRIGGER IF EXISTS` first → **idempotent, no duplicates/orphans**.
- BEFORE-UPDATE timing is correct for `updated_at`. No conflicting/duplicate triggers.
- **Future compatibility:** `on_auth_user_created` survives OAuth/OTP signups (any
  `auth.users` insert provisions a profile).

---

## 6. Stage 5 — RLS review

| Table | SELECT | INSERT | UPDATE | DELETE | Notes |
|---|---|---|---|---|---|
| `profiles` | own **or** admin | own (`auth.uid()=id`) | own **without role change** (`WITH CHECK` compares stored role) + admin-any | — | **C-1 closed**: role self-escalation blocked ✅ |
| `products` | public (`true`) | admin | admin | admin | public read + admin write (OR-combined) ✅ |
| `categories` | public | admin | admin | admin | ✅ |
| `cart_items` | owner (ALL) | owner | owner | owner | `FOR ALL USING/WITH CHECK auth.uid()=user_id` ✅ |
| `wishlists` | owner (ALL) | owner | owner | owner | ✅ |
| `orders` | own or admin | **none** (blocked) | admin | — | creation only via `place_order()` (D-RLS-4) ✅ |
| `order_items` | owner **or** admin | **blocked** (`WITH CHECK false`) | — | — | writes only via `place_order` (DEFINER) ✅ |
| `storage.objects` (products) | public read | admin | admin | admin | via `is_admin()` ✅ |

- **RLS enabled on all seven public tables** (baseline + re-asserted in 004).
- **Role-escalation prevention:** `profiles_update_own` `WITH CHECK` requires
  `role = (SELECT role FROM profiles WHERE id = auth.uid())`; admin changes gated by a
  separate `is_admin()` policy. ✅
- **Recursion:** the `profiles` self-referencing subquery resolves via the SELECT policy,
  whose admin branch uses **DEFINER** `is_admin()` (RLS-bypassing) → **no infinite
  recursion**. *Verify on staging as a smoke test.*
- **R-5 (Info):** baseline `GRANT ALL … TO anon` on tables is broad, but every table has
  RLS enabled, so anon is row-constrained (standard Supabase posture). No action required.

---

## 7. Stage 6 — Storage review

- Bucket `products` created **public** (`006`), idempotent (`ON CONFLICT DO NOTHING`).
- Policies: public `SELECT`; admin `INSERT/UPDATE/DELETE` via `is_admin()`, all scoped to
  `bucket_id = 'products'`. ✅
- **Frontend alignment (WS2):** `adminService.uploadImages` uploads then
  `getPublicUrl` (fixed to `{ data: { publicUrl } }`) and persists URLs to
  `products.images` (jsonb) — consistent with a **public** bucket. ✅
- **R-6 (Manual, Medium):** live bucket existence/visibility is an unresolved decision
  (Reconciliation Decision Log Q2). Confirm on the dashboard before/after applying `006`;
  the `INSERT … ON CONFLICT DO NOTHING` will not change an existing bucket's `public` flag,
  so if a private `products` bucket already exists, public reads via `getPublicUrl` will
  fail — reconcile visibility manually.
- No signed-URL usage (public bucket) — acceptable for product imagery.

---

## 8. Stage 7 — Auth review

- **Profile creation:** automatic via `on_auth_user_created` → `handle_new_user` (role
  `'customer'`). Matches `AuthContext.signup` metadata (`full_name`, `phone`). ✅
- **Role handling:** canonical `'customer' | 'admin'`; CHECK enforced in `007`; admin
  promotion is admin-only (RLS) — no client path. ✅
- **Future OAuth/OTP:** providers and MFA/OTP present-but-disabled in `config.toml`; the
  signup trigger is provider-agnostic, so OAuth/OTP will provision profiles unchanged. ✅
- **R-7 (Manual, prod):** `enable_confirmations=false` (email verification off) and
  `minimum_password_length=6`. For production, consider enabling email confirmation and
  raising password length to ≥8; configure SMTP (`[auth.email.smtp]`) — local Inbucket does
  not send real mail.
- **R-8 (Manual, prod):** `site_url`/`additional_redirect_urls` are localhost; set to the
  production domain before rollout (else auth redirects/email links break).

---

## 9. Stage 8 — Performance review

- **Indexes (010):** cover FK joins (`order_items.order_id/product_id`,
  `cart_items/wishlists.product_id`, `products.category_id`), order listing
  (`orders.user_id`, `orders.created_at DESC`, `orders.status`), `products.is_active`,
  `products.slug`, and product search (GIN FTS on name+description). Good coverage of the
  known access paths. ✅
- **N+1 / joins:** frontend reads embed relations (`products(*)`, `categories(...)`,
  `order_items(*)`, `profiles(...)`) — single round-trips, not N+1. `place_order` is
  set-based except the small stock-validation loop (fine for MVP cart sizes).
- **Locking:** `place_order` `FOR UPDATE OF p` scopes locks to the cart's products only.
- **Recommendations (optional):**
  - **P-1 (Low):** composite `orders (user_id, created_at DESC)` would serve "my orders,
    newest first" with one index (currently two single-column indexes).
  - **P-2 (Low):** FTS uses the `simple` dictionary (no stemming); `english` would improve
    recall if desired.
  - **P-3 (Info):** `products.featured` is **not** used for filtering (Home shows newest 8
    via `limit: 8`), so no `featured` index is needed today. Likewise `is_active` has no
    frontend read yet — its index is pre-provisioned and harmless.
  - **P-4 (Low):** prefer the documented `CONCURRENTLY` index variant on production if
    tables are large enough that a brief write lock is unacceptable.

---

## 10. Security review (synthesis)

| Control | Status |
|---|---|
| No `service_role`/secrets in frontend | ✅ (verified WS2) |
| Client cannot set order totals | ✅ (`place_order` server-computes) |
| Order creation server-only | ✅ (orders INSERT blocked; order_items `WITH CHECK false`) |
| Role escalation blocked | ✅ (`profiles_update_own` WITH CHECK) |
| RLS on all public tables | ✅ |
| Storage writes admin-gated | ✅ |
| `SECURITY DEFINER` + pinned `search_path` | ✅ (all definer fns set `search_path=public`) |
| RPC least privilege | ✅ `place_order` (authenticated only); ⚠️ `is_admin`/`handle_new_user`/`set_updated_at` retain anon EXECUTE (R-2/R-3, non-exploitable — optional revoke) |
| Secrets in `config.toml` | ✅ all via `env(...)` substitution; none hard-coded |

No critical or high security defects. Two **low** least-privilege hardening opportunities
(R-2/R-3).

---

## 11. Dependency graph & canonical conformance

- Every `Reconciliation_Decision_Log` item is implemented **exactly once** in the chain
  (cross-checked in `Phase1_7B_Migration_Review.md`): D-KEY-2/4/5 (005), D-RLS-3/4 + C-1
  (004), D-ENUM-1 (008), D-CUST-1 role (003/007), D-PROD-* columns (002), storage M8 (006),
  indexes/FTS §5 (010).
- Frontend (WS2) targets the **post-migration** schema; backend supplies exactly those
  objects. Cross-workstream couplings:
  - checkout ⇒ `003` (`place_order`); cart/wishlist ⇒ `004` (owner RLS);
    category embed/filter ⇒ `009` (FK); **product `description` read/write ⇒ `008`**
    (column is `"Description"` until renamed — admin product create/update and detail
    display require `008`).

---

## 12. Remaining manual tasks (highlighted)

| # | Task | When | Blocking? |
|---|---|---|---|
| M-1 | `supabase migration repair --status applied 001` (adopt baseline onto empty live history), then confirm `supabase db diff --linked` is clean | before any push | **YES** — push of `001` to live fails without it |
| M-2 | Run the 4 read-only pre-checks: product `id` uniqueness (gates 008), cart/wishlist duplicate scan (gates 007/009), storage bucket existence/visibility (006), distinct `orders.status` + `profiles.role` values | before 007/008 | **YES** for gated steps |
| M-3 | Fresh backup + approval + maintenance window before `007` and `008` | before gated apply | **YES** |
| M-4 | Post-apply `VALIDATE CONSTRAINT` for the NOT VALID FKs (`orders/cart_items/wishlists.user_id`, `cart_items/wishlists/order_items.product_id`) after orphan check | after 005/009 | No (enforced for new rows already) |
| M-5 | Reconcile legacy `orders.status` values (`007` leaves `orders_status_check` NOT VALID; `'paid'` is **not** in the allowed set and has no auto-map), then `VALIDATE CONSTRAINT orders_status_check` | after 007 | No (new writes already constrained; app never writes `'paid'` to status) |
| M-6 | Confirm no duplicate `products.slug`, then optionally swap `idx_products_slug` for the UNIQUE `CONCURRENTLY` variant | after 010 | No |
| M-7 | Production auth/config: real `site_url`+redirects, SMTP, consider email confirmation + password length ≥8 (R-7/R-8) | before prod | prod-blocking |
| M-8 | **Docs drift:** update `Migration_History.md` (still says "no forward migrations authored"; only lists 001) to record `002`–`010`; reconcile the file-naming convention note (doc prescribes timestamped names, files use `NNN_`) | repo hygiene | No |
| M-9 | Add a `supabase/seed.sql` (even empty) or set `db.seed.enabled=false` — `config.toml` references a non-existent `./seed.sql`, which breaks `supabase db reset` locally | repo hygiene | No (local only) |
| M-10 | (Recommended) apply `cart_items` UNIQUE before enabling checkout **or** aggregate cart by product in `place_order` (R-1) | before checkout on prod | recommended |

---

## 13. Stage 9 — Production readiness

| Capability | Ready? | Notes |
|---|---|---|
| Staging deployment | ✅ | after M-1; apply 002–006, smoke test |
| Migration execution | ✅ (with gates) | chain valid/ordered/idempotent; 007/008 need M-3 approvals |
| Production rollout | ⚠️ conditional | gated approvals + backup + M-7 prod config |
| Rollback | ✅ (mixed) | additive/constraint/index steps: `DROP …`; 007/008: **restore-from-backup** (documented) |
| Backup/recovery | ⚠️ manual | take PITR/snapshot before 007/008 (M-3) |
| Zero-downtime | ✅ mostly | 002–006, 009, 010 online; 008 briefly locks `products`; 010 plain `CREATE INDEX` locks writes (use CONCURRENTLY if large) |

**Production Readiness Score: 8.6 / 10** (points withheld for the mandatory manual gates,
the two doc-drift items, and the missing `seed.sql`).

---

## 14. Risk register

| ID | Risk | Sev | Likelihood | Mitigation |
|---|---|---|---|---|
| R-1 | `place_order` stock decrement wrong if duplicate cart rows exist pre-`009` | Med | Low | app merges; `007` dedupes; apply UNIQUE early or aggregate in fn (M-10) |
| M-1 | Pushing `001` to live without repair fails (dup type/policies) | High | High if skipped | run `migration repair` first (M-1) |
| M-5 | `orders_status_check` VALIDATE fails on legacy `'paid'`/unknown status | Med | Med | reconcile values then VALIDATE (M-5) |
| R-6 | Existing private `products` bucket → broken public image reads | Med | Low | confirm/adjust bucket visibility (M-2/R-6) |
| R-2/R-3 | `anon` EXECUTE on `is_admin`/`handle_new_user`/`set_updated_at` | Low | n/a | optional REVOKE (non-exploitable) |
| 008 | `products` PK swap briefly locks; aborts on duplicate `id` | Med | Low | guard aborts cleanly; run in window |
| 007 | Data mutation not reversible in place | Med | — | backup first; gated |
| DOC | `Migration_History.md` stale / naming mismatch | Low | Certain | update doc (M-8) |
| CFG | `seed.sql` missing but referenced | Low | Certain (local reset) | add file or disable (M-9) |
| AUTH | Localhost `site_url`, email confirm off, min pw 6 | Med | — | prod hardening (M-7) |

No **Critical** open items; the one High item (M-1) is a well-documented, mandatory
pre-step, not a defect.

---

## 15. GO / NO-GO

**GO — for staging** (execute M-1, then apply `002`–`006`, run backend + frontend smoke
tests).

**CONDITIONAL GO — for production**, conditioned on: M-1 (repair), M-2/M-3 (pre-checks +
backup + approvals for `007`/`008`), M-4/M-5 (post-apply VALIDATE + legacy status
reconciliation), and M-7 (prod auth/config). Addressing R-1 (M-10) before enabling checkout
is recommended. The two doc/config hygiene items (M-8, M-9) do not block deployment.

**Engineering score: 9.2 / 10.** The backend is a clean, canonical, well-documented,
forward-only chain with sound server logic and security. Deductions: R-1 robustness,
R-2/R-3 least-privilege polish, and repository hygiene drift (M-8/M-9).

---

**STOP.** Report produced. No database was contacted; no migration was executed, pushed,
or repaired; nothing was committed, branched, or tagged. Awaiting approval before any
execution (Runbook §1) or Workstream continuation.
