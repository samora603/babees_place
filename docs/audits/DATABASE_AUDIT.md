# Database Audit — Babees Place

Auditor role: Database Engineer
Date: 2026-07-12
Source of truth: `supabase/migrations/001_schema_rls_place_order.sql`.
Verification limit: Non-migrated tables (`products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`) exist only on the remote and are **UNVERIFIED**; their design below is inferred from frontend queries.

---

## Summary score: 5 / 10

Core design (profiles/orders/order_items/cart) is normalized, uses UUID PKs, `TIMESTAMPTZ` timestamps, `NUMERIC(12,2)` money, and cascade FKs — solid fundamentals. It loses points for: **no indexes**, **incomplete/irreproducible schema**, inconsistent naming (quoted camelCase columns), no `categories` normalization, and no auto-`updated_at`.

---

## 1. Entity model (verified tables)

```
auth.users ──1:1──> profiles (role: user|admin)
auth.users ──1:N──> orders ──1:N──> order_items ──N:1──> products*
auth.users ──1:N──> cart ──N:1──> products*
```
(* `products` is not in migrations.)

| Table | PK | FKs | Timestamps | Constraints |
|---|---|---|---|---|
| `profiles` | `id` = `auth.users.id` | CASCADE | `created_at`, `updated_at` | `role CHECK IN (user,admin)` |
| `orders` | `id` uuid | `user_id`→auth.users CASCADE | `created_at`, `updated_at` | defaults on status/total/payment |
| `order_items` | `id` uuid | `order_id`→orders CASCADE, `product_id`→products (no cascade) | `created_at` | `quantity > 0` |
| `cart` | `id` uuid | `user_id`→users CASCADE, `product_id`→products CASCADE | `created_at` | `UNIQUE(user_id, product_id)`, `quantity > 0` |

---

## 2. Strengths
- UUID surrogate keys via `gen_random_uuid()`.
- `TIMESTAMPTZ` (timezone-aware) everywhere.
- Monetary values use `NUMERIC(12,2)` (no float rounding).
- Referential integrity with `ON DELETE CASCADE` where appropriate.
- Order items **snapshot** name/price/image → order history is immutable even if the product later changes. Good commerce practice.
- Legacy-column migration guards (`order_status`→`status`, `total_price`→`total_amount`, `image`→`image_url`) show awareness of drift.

---

## 3. Weaknesses & risks

### 3.1 No indexes (HIGH)
No `CREATE INDEX` exists. Missing at minimum:
- `orders(user_id)`, `orders(created_at)` — used by `getMyOrders`, admin list ordering.
- `order_items(order_id)` — used by every order join.
- `cart(product_id)`, `order_items(product_id)` — FK lookups/joins.
- (Inferred `products`) `products(category)`, `products(slug)`, `products(name)` for search/filter (`productService.getProducts` uses `ilike name`, `eq category`, `gte/lte price`).
Without these, list/search/join queries seq-scan and degrade with volume.

### 3.2 Schema not reproducible (HIGH)
`products` and 5 other tables are absent from migrations; `20260617042152_remote_schema.sql` is empty. `supabase db reset` yields a broken app. See SUPABASE_AUDIT §2.

### 3.3 Categories not normalized (MEDIUM)
`products.category` is free-text (`productService.getCategories` does `SELECT category` then `[...new Set()]`). Meanwhile `adminService` has full CRUD against a `categories` table. Two competing models; the text approach prevents FK integrity, renaming, and per-category metadata.

### 3.4 Naming inconsistency (MEDIUM)
`place_order` references `p."discountPrice"` (quoted camelCase) alongside snake_case columns (`image_url`, `total_amount`). Mixed identifier casing is fragile in Postgres (quoted identifiers are case-sensitive) and violates the project's own lowercase/snake_case convention. Standardize to `discount_price`.

### 3.5 No `updated_at` automation (LOW/MEDIUM)
`updated_at` only updates when application code sets it. Add a `BEFORE UPDATE` trigger to keep it accurate.

### 3.6 Integrity/consistency (see SECURITY_AUDIT)
- `order_items.price`/`orders.total_amount` are client-writable through RLS on the fallback path.
- `place_order` lacks row locking → oversell race.

### 3.7 Data typing gaps (LOW)
- `orders.status` / `payment_status` are free `TEXT` with defaults but **no CHECK constraint**, while the frontend defines fixed enums (`constants.js`: pending/processing/shipped/delivered/cancelled; pending/paid/failed/refunded). Add `CHECK` constraints or an enum type to prevent invalid states.
- `profiles.email` duplicates `auth.users.email` (denormalized copy that can drift).

---

## 4. Normalization assessment
- Verified tables are ~3NF. The main violations are (a) `products.category` free-text (should reference `categories`), and (b) `profiles.email` duplication. Order-item snapshotting is an intentional, acceptable denormalization.

---

## 5. Scalability outlook
- UUID + Postgres scales fine for the expected volume; the immediate scaling blockers are **missing indexes** and **full-table scans** (`getCategories`, unindexed search).
- Future: consider `products` full-text search (`tsvector` + GIN) instead of `ilike '%…%'` (which cannot use a b-tree index and scans every row); partial index on low stock (`WHERE stock < 5`) for the admin low-stock query; pagination is already range-based (good).

---

## 6. Recommendations (priority)
1. `supabase db pull` → commit the complete schema; remove the empty migration.
2. Add all FK/search indexes listed in §3.1.
3. Fix `profiles_update_own` RLS (CRITICAL, cross-ref SECURITY_AUDIT).
4. Add `CHECK` constraints / enums for `orders.status`, `payment_status`.
5. Decide one categories model; migrate `products.category` to a FK if keeping the table.
6. Add `updated_at` trigger; rename `"discountPrice"` → `discount_price`.
7. Add `FOR UPDATE` locking in `place_order`; forbid client-side order/item writes.
8. Introduce full-text search for products before catalog grows.
