# Supabase Audit — Babees Place

Auditor role: Backend / Supabase Engineer
Date: 2026-07-12
Scope: `supabase/` directory + all Supabase calls in `frontend/src`.
Verification limit: The remote project (`qfcygrxrfszcdltangec`) was not queried. Anything not present in `supabase/migrations/` is **UNVERIFIED**.

---

## Summary score: 5 / 10

The parts that exist are competently written (auto-profile trigger, `is_admin()` helper, atomic `place_order` RPC, RLS on core tables). The problem is **coverage**: the migration set defines only 4 of the ~11 tables the app uses, the "remote schema" migration is empty, no indexes are declared, and storage/realtime configuration is unverified.

---

## 1. What is actually defined in migrations

File: `supabase/migrations/001_schema_rls_place_order.sql` (7,984 bytes)

| Object | Type | Notes |
|---|---|---|
| `public.profiles` | table | PK = `auth.users(id)`, `role CHECK IN ('user','admin')`, timestamps ✅ |
| `handle_new_user()` | trigger fn | `SECURITY DEFINER`, `search_path=public`, auto-creates profile on signup ✅ |
| `on_auth_user_created` | trigger | AFTER INSERT on `auth.users` ✅ |
| `is_admin()` | fn | `STABLE SECURITY DEFINER`, `search_path=public` ✅ |
| `public.orders` | table | + legacy-column migration (`order_status`→`status`, `total_price`→`total_amount`) |
| `public.order_items` | table | snapshot fields (name/price/qty/image_url) |
| `public.cart` | table | `UNIQUE(user_id, product_id)`, qty check ✅ |
| RLS policies | — | on `profiles`, `cart`, `orders`, `order_items` (see below) |
| `place_order(uuid)` | RPC | `SECURITY DEFINER`, atomic checkout ✅ |

File: `supabase/migrations/20260617042152_remote_schema.sql` — **0 bytes (empty).**

---

## 2. Missing tables (referenced by code, absent from migrations)

| Table | Referenced in | Impact |
|---|---|---|
| `products` | everywhere (`productService`, `cart`, `place_order`, admin) | Core table not in VCS; columns only inferred: `id, name, price, "discountPrice", category, slug, stock, image_url, images(jsonb)` |
| `categories` | `adminService.createCategory/updateCategory/deleteCategory` | Table CRUD exists in code, but `productService.getCategories` derives categories from `products.category` text instead — **contradiction / dead admin code** |
| `wishlist` | `wishlistService`, `WishlistContext` (realtime) | Not in migrations |
| `payments` | `paymentService` | Not in migrations; also just a stub |
| `pickup_locations` | `adminService`, `AdminPickupLocations.jsx` | Not in migrations |
| `addresses` | `userService.getAddresses/addAddress/...` | Not in migrations |
| `settings` (implied) | `AdminSettings.jsx` | Page is a placeholder; no table |

Because the "remote schema" dump is empty, **the database is not reproducible from source**. A fresh `supabase db reset` would produce a schema that the frontend cannot run against.

---

## 3. RLS review

Verified (in migration 001):
- ✅ RLS **enabled** on `profiles`, `cart`, `orders`, `order_items`.
- ✅ `cart_all_own`: `FOR ALL USING/WITH CHECK (auth.uid() = user_id)` — correct.
- ✅ `orders_select_own`: owner OR admin.
- ✅ `orders_insert_own`: `WITH CHECK (auth.uid() = user_id)`.
- ✅ `orders_update_admin`: admin only.
- ✅ `order_items_select` / `order_items_insert_own`: scoped through parent order ownership.
- ❌ **`profiles_update_own` has no `WITH CHECK` and allows role self-escalation** — see SECURITY_AUDIT C-1 (CRITICAL).
- ⚠️ `order_items_insert_own` lets the client set arbitrary `price`/`name` for its own order (integrity risk — see SECURITY_AUDIT H-1).

Unverified (not in migrations): RLS on `products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`. Per ADR-006 every table must have RLS; this must be proven.

---

## 4. Functions / RPC

- `place_order(p_user_id uuid)` — well designed: authorization check (`auth.uid()` vs param, or admin), server-side stock validation, server-side total (`COALESCE(discountPrice, price) * qty`), atomic insert of order + items, stock decrement, cart clear, `GRANT EXECUTE ... TO authenticated`. ✅
  - Gaps: no `SELECT ... FOR UPDATE` row lock → oversell race under concurrency; reads `p."discountPrice"` (quoted camelCase column) and `p.images::jsonb` — confirms `products` uses mixed-case/JSON columns (schema smell, and only works if that column shape exists remotely).
- No **Edge Functions** exist (`supabase/functions/` absent). ADR-003 anticipated them for business logic; payments/M-Pesa will require them.

---

## 5. Indexes / constraints

- **No `CREATE INDEX` statements anywhere.** Foreign-key columns `orders.user_id`, `order_items.order_id`, `order_items.product_id`, `cart.product_id` have **no supporting indexes**, so ownership filters and joins (e.g. `getMyOrders`, cart+products join) will sequential-scan as data grows.
- Constraints present are good where defined (PKs, FKs with `ON DELETE CASCADE`, `CHECK (quantity > 0)`, `UNIQUE(user_id, product_id)` on cart).
- No `updated_at` auto-update trigger; `updated_at` is only set manually in `adminService.updateOrderStatus`, so it drifts elsewhere.

---

## 6. Configuration (`config.toml`)

- `project_id = "frontend"` — misleading; should be the project name.
- `[auth]` `enable_confirmations = false`, `minimum_password_length = 6`, no password complexity, no captcha — weak for production (see SECURITY_AUDIT M-2).
- `site_url = http://127.0.0.1:3000` but Vite dev server runs on **5173** (`vite.config.js`) — mismatch; also `additional_redirect_urls` uses `https://127.0.0.1:3000` (wrong scheme/port). Redirect allow-list is inconsistent.
- Storage enabled, 50 MiB limit, S3 protocol on — but **no buckets declared**.
- `db.seed` points to `./seed.sql`, which **does not exist**.
- Realtime enabled; the app subscribes to `cart` and `wishlist` changes.

---

## 7. Realtime

- `hooks/useCart.js` and `WishlistContext.jsx` open channels on `public.cart` / `public.wishlist`. Realtime must be enabled per-table (publication) on the remote — **UNVERIFIED**. Each event triggers a full re-fetch (coarse-grained; see PERFORMANCE_AUDIT).

---

## 8. Recommendations (priority order)

1. **Fix `profiles_update_own`** (CRITICAL, see SECURITY_AUDIT C-1).
2. **Dump and commit the full remote schema** into a real migration (`supabase db pull`) so `products`, `wishlist`, `payments`, `pickup_locations`, `addresses`, `categories` are versioned; delete the empty `20260617042152_remote_schema.sql` or fill it.
3. **Prove/add RLS** on every remaining table.
4. **Add indexes** on all FK columns and common filters (`products.category`, `products.slug`, `orders.user_id`, `orders.created_at`, `order_items.order_id`).
5. **Remove client order fallback**; keep `place_order` the only write path; add `FOR UPDATE` locking.
6. **Declare storage buckets + object policies** in config/migrations; fix `getPublicUrl` destructuring.
7. **Reconcile categories**: pick one model (real `categories` table *or* text field) and delete the other path.
8. Fix `config.toml` `site_url`/redirect URLs and `project_id`; add the referenced `seed.sql` or disable seeding.
9. Add `updated_at` trigger; normalize `products` column naming (avoid quoted `"discountPrice"`).
10. Plan Edge Functions for payments (M-Pesa) and any privileged mutations.
