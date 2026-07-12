# Database — Technical Reference

Status: Updated during Phase 1.
Source of truth: `supabase/migrations/001_schema_rls_place_order.sql` plus the Phase 1 migrations below.
⚠️ Several tables the application uses are **not present in migrations** and exist only on the live Supabase project — they are documented here as *inferred* and marked **UNVERIFIED**. Do not treat inferred columns as authoritative until a baseline migration is generated (`supabase db pull`).

### Phase 1 migrations (authored, MANUAL-APPLY ONLY — not yet applied)
- `002_phase1_security_hardening.sql` — `profiles` role-escalation `WITH CHECK`, admin-only role updates, removal of direct `orders`/`order_items` INSERT policies, and `place_order()` row locking (`FOR UPDATE`).
- `003_phase1_indexes_constraints.sql` — indexes on `orders`/`order_items`/`cart`, `NOT VALID` CHECK constraints on `orders.status`/`payment_status`, and a shared `set_updated_at()` trigger. Product indexes + full-text search are included as a commented, deferred block pending the baseline.

**Baseline generation (still required):** the repo schema is incomplete. Run `supabase db pull` against the live project to capture the real objects before applying 002/003.

### ⚠️ VERIFIED live schema (2026-07-12) — repo migrations DO NOT match live
Captured read-only via `supabase db dump --linked -s public` from project `qfcygrxrfszcdltangec`. The live database was built **manually** (remote migration history is empty) and does **not** match migration `001` or the frontend's assumptions. Actual live objects:

| Live table | Key columns (actual) | Mismatch vs repo/code |
|---|---|---|
| `cart_items` | id, user_id, product_id, quantity (smallint), created_at | Code/001 expect table **`cart`** with `UNIQUE(user_id,product_id)` + FKs; live has no unique/FK, different name |
| `categories` | id, name, slug, created_at | Exists (resolves the "categories model" contradiction — it IS a table) |
| `order_items` | id, order_id, product_id, quantity (smallint), price, name | Live has **no** `image_url`, **no** `created_at`; INSERT blocked by policy `WITH CHECK (false)` |
| `orders` | id, user_id, **`total`**, status (text), created_at | Code/001 use **`total_amount`**; live has **no** `payment_status`, `note`, `updated_at` |
| `products` | id, name, slug, price, category (text), category_id, featured, created_at, **`"Description"`** | Live has **no** `stock`, `discountPrice`, `image_url`, `images`, `is_active`; **PK is composite `(id, name)`**; capital-D `"Description"` |
| `profiles` | id, email, **role default `'customer'`**, created_at (timestamptz), phone | Live has **no** `full_name` (code writes it!); no `role` CHECK; no `updated_at` |
| `wishlists` | id, user_id, product_id, created_at | Code expects **`wishlist`** (singular) |

**Functions:** none in `public` — `place_order()`, `is_admin()`, `handle_new_user()` from `001` are **absent on live**.
**Triggers/Indexes:** none beyond primary keys.
**RLS:** enabled on all 7 tables. Policies exist only for `orders`, `order_items` (`Block direct insert order items` = `WITH CHECK (false)`), `products` (public SELECT), and `profiles`. **`cart_items`, `categories`, `wishlists` have RLS enabled but NO policies → effectively deny-all** for anon/authenticated.

Consequence: substantial parts of the app cannot work against this live DB unchanged, and migrations `001`/`002`/`003` cannot be applied as-is. See `docs/audits/Phase1_Final_Closure_Report.md`.

---

## 1. Overview

- Engine: PostgreSQL (managed by Supabase), `major_version = 17` (`supabase/config.toml`).
- Access: via `@supabase/supabase-js` from the frontend `services/` layer, plus one RPC (`place_order`).
- Authorization: enforced in-database with Row Level Security (RLS). See `docs/03_Security.md`.

## 2. Tables defined in migrations (authoritative)

### `public.profiles`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | FK → `auth.users(id)` ON DELETE CASCADE |
| `email` | text | denormalized copy of auth email |
| `full_name` | text | |
| `phone` | text | |
| `role` | text | `CHECK (role IN ('user','admin'))`, default `'user'` |
| `created_at` | timestamptz | default `now()` |
| `updated_at` | timestamptz | default `now()` (not auto-updated — no trigger) |

Auto-created on signup by trigger `on_auth_user_created` → `handle_new_user()` (SECURITY DEFINER).

### `public.orders`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | `gen_random_uuid()` |
| `user_id` | uuid | FK → `auth.users(id)` CASCADE |
| `status` | text | default `'pending'` (no CHECK; app enum: pending/processing/shipped/delivered/cancelled) |
| `total_amount` | numeric(12,2) | default 0 |
| `payment_status` | text | default `'pending'` (app enum: pending/paid/failed/refunded) |
| `note` | text | |
| `created_at` / `updated_at` | timestamptz | |

Migration includes legacy-rename guards: `order_status`→`status`, `total_price`→`total_amount`.
> Note: `orderService.mapOrder` also reads `delivery_type`, `pickup_location`, `delivery_address`, `mpesa_receipt_number` — these columns are **not** in migration 001 (UNVERIFIED / remote-only).

### `public.order_items`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `order_id` | uuid | FK → `orders(id)` CASCADE |
| `product_id` | uuid | FK → `products(id)` (no cascade) |
| `name`, `price`, `quantity`, `image_url` | snapshot fields | `quantity > 0` |
| `created_at` | timestamptz | |

Snapshots product data so order history stays stable if products change.

### `public.cart`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid | FK → `auth.users(id)` CASCADE |
| `product_id` | uuid | FK → `products(id)` CASCADE |
| `quantity` | int | default 1, `CHECK (quantity > 0)` |
| `created_at` | timestamptz | |
| — | — | `UNIQUE (user_id, product_id)` |

## 3. Tables used by the app but NOT in migrations (UNVERIFIED / remote-only)

| Table | Referenced in | Inferred columns |
|---|---|---|
| `products` | everywhere | `id, name, price, "discountPrice", category, slug, stock, image_url, images(jsonb)` |
| `categories` | `adminService` CRUD | `id, name` (contradicts text-based `products.category`) |
| `wishlist` | `wishlistService`, realtime | `user_id, product_id` |
| `payments` | `paymentService` (stub) | unknown |
| `pickup_locations` | `adminService` | unknown |
| `addresses` | `userService` | `user_id, …` |

**Action required (Phase 1):** run `supabase db pull` to generate a baseline migration so these are versioned. Do not hand-write speculative migrations.

## 4. Functions / RPC
- `handle_new_user()` — trigger fn, SECURITY DEFINER, `search_path=public`.
- `is_admin()` — STABLE SECURITY DEFINER; returns whether `auth.uid()` has `role='admin'`.
- `place_order(p_user_id uuid)` — SECURITY DEFINER atomic checkout: authorization check, server-side stock validation, server-side total (`COALESCE("discountPrice", price) * qty`), inserts order + items, decrements stock, clears cart. Granted to `authenticated`.

## 5. Known issues (see `docs/audits/DATABASE_AUDIT.md`)
- No indexes declared (FK/search columns).
- Schema not reproducible (empty `20260617042152_remote_schema.sql`).
- `profiles` UPDATE RLS allows role self-escalation (CRITICAL — see Security).
- Mixed identifier casing (`"discountPrice"`).
- No `updated_at` trigger; no status CHECK constraints.
- `place_order` lacks row-level locking (oversell race).

## 6. Conventions (target)
- snake_case identifiers; UUID PKs; `timestamptz` timestamps; `numeric(12,2)` for money; RLS on every table; index every foreign key.
