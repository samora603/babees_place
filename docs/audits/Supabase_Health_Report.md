# Phase 0 — Supabase Health Report

Auditor: Backend / Supabase Engineer
Date: 2026-07-12
Scope: `supabase/` + all Supabase calls in `frontend/src`.
Verification limit: The **live project was not accessed** (`ref: qfcygrxrfszcdltangec`). Anything not in `supabase/migrations/` is **UNVERIFIED**. Per Phase 0 rules, **no migrations were fabricated**.
Cross-reference: `docs/audits/SUPABASE_AUDIT.md`, `docs/technical/02_Database.md`.

---

## 1. Migrations
| File | Size | Contents |
|---|---|---|
| `001_schema_rls_place_order.sql` | 7,984 B | `profiles`, `orders`, `order_items`, `cart`, RLS, `handle_new_user()`, `is_admin()`, `place_order()` RPC |
| `20260617042152_remote_schema.sql` | **0 B (empty)** | nothing |

**Migration history is incomplete.** The empty "remote schema" file suggests a `supabase db pull` was started but never captured output.

## 2. Repository schema vs live project — MISMATCH (documented, not fixed)
Tables the frontend queries that are **absent from migrations** (exist only on the live project):
`products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`.

Evidence: import/usage grep across `services/` (see `technical/02_Database.md` for the reference table).

**Consequence:** `supabase db reset` from this repo would produce a schema the app cannot run against. The database was effectively **built manually / out-of-band**.

**Recommendation (do NOT fabricate):**
```bash
# From an authenticated environment linked to the project:
supabase link --project-ref qfcygrxrfszcdltangec
supabase db pull            # generate a real baseline migration from the live schema
# review, then commit; remove/replace the empty 20260617042152_remote_schema.sql
```
This is the single most important backend action for Phase 1. It must be run by someone with project access; it was **not** performed here because the live project was not accessed.

## 3. RLS
Verified (migration 001): enabled on `profiles`, `cart`, `orders`, `order_items` with sensible owner/admin policies.
- ❌ **`profiles_update_own` lacks `WITH CHECK`** → role self-escalation (CRITICAL; see Security Baseline).
- ⚠️ `order_items_insert_own` lets the client set arbitrary `price`/`name`.
- **UNVERIFIED:** RLS on `products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`. Per ADR-006 every table must have RLS — must be proven after `db pull`.

## 4. Functions / RPC
- `handle_new_user()`, `is_admin()` — SECURITY DEFINER with `search_path=public` (good).
- `place_order()` — atomic, server-side totals & stock checks (good); lacks `FOR UPDATE` locking (oversell race).

## 5. Storage
- `config.toml`: storage enabled, 50 MiB limit, S3 protocol on; **no buckets declared** (`[storage.buckets.*]` commented out).
- Code uses a `products` bucket (`adminService.uploadImages`); existence + public/private + object policies **UNVERIFIED**.
- Bug: `getPublicUrl` destructured as `{ publicURL }` (should be `{ data: { publicUrl } }`).

## 6. Edge Functions
- **None** (`supabase/functions/` does not exist). Payments (`paymentService`) are a client stub. M-Pesa/PSP integration and any privileged server logic will require Edge Functions.

## 7. Auth configuration (`config.toml`)
- Weak: `minimum_password_length = 6`, no complexity, email `enable_confirmations = false`, no captcha.
- `site_url = http://127.0.0.1:3000` and redirect `https://127.0.0.1:3000` — **mismatched** with Vite port 5173 and scheme. Fix before deploy.
- `project_id = "frontend"` — misleading label.
- `db.seed` → `./seed.sql` which **does not exist**.

## 8. Realtime
- App subscribes to `cart` and `wishlist` changes; requires table publications on the remote (**UNVERIFIED**). Each event triggers a full re-fetch (coarse).

## 9. Health score: **5/10**
Solid core (RPC, trigger, RLS on core tables); blocked by irreproducible schema, unverified RLS/storage, one critical policy flaw, and config mismatches.

## 10. Phase 1 actions (priority)
1. `supabase db pull` → commit baseline; remove empty migration.
2. Fix `profiles_update_own` (CRITICAL).
3. Prove/add RLS on all remaining tables.
4. Add FK/search indexes (see Database docs).
5. Declare storage buckets + policies; fix `getPublicUrl`.
6. Correct `config.toml` (`site_url`, redirects, `project_id`, seed).
7. Add `FOR UPDATE` locking to `place_order`; remove client order fallback.
8. Plan Edge Functions for payments.
