# Canonical Schema Proposal

**Date:** 2026-07-12
**Basis:** `docs/database/Schema_Comparison_Matrix.md` (evidence: live dump + repo + frontend).
**Governing principle:** The **live database is the source of truth**. Changes to live are preferred **additive and non-destructive**. Any rename, primary-key change, type change, or data normalization is proposed **for explicit human approval** and is not executed here.

> Where evidence is missing (storage buckets, auth settings), this proposal says so
> and defers the decision rather than assuming.

---

## Guiding rules for choosing canonical

1. **Prefer code changes over destructive DB changes.** Renaming a live table
   (`cart_items` → `cart`) risks breaking anything already pointing at it and needs
   approval; updating frontend identifiers is cheap and reversible.
2. **Add, don't remove.** Missing columns the app genuinely needs (`stock`,
   `full_name`, `place_order()`) are added. We do not drop live columns.
3. **Keep the stricter security posture.** Where live is *safer* than the repo
   (e.g., `order_items` INSERT blocked with `WITH CHECK (false)`), live wins.
4. **Defer feature-shaped gaps.** `payments` / `pickup_locations` tables are only
   created if those features are in scope for Phase 2 — otherwise the code paths are
   disabled. This avoids building new features under a stabilization mandate.

---

## Canonical decisions

### 1. Table naming: adopt live names in code
- **Decision:** Canonical = `cart_items` and `wishlists` (live names).
- **Why:** Live is source of truth; renaming live tables is a destructive-class op
  requiring approval and coordination. The frontend already isolates access in
  `cartService`/`wishlistService`, so the change is small and contained.
- **Trade-offs:** Code churn in 2 services + 2 contexts + realtime channel table name.
- **Frontend impact:** Change `.from('cart')` → `.from('cart_items')`,
  `.from('wishlist')` → `.from('wishlists')`, and the realtime `table: 'wishlist'`.
- **Data impact:** None.
- **Future impact:** Names become consistent; a later cosmetic rename remains possible.
- **Alternative (needs approval):** Rename live tables to `cart`/`wishlist` via
  `ALTER TABLE ... RENAME`. Preserves data but is approval-gated and higher risk.

### 2. `orders` total column: keep `total`, adapt code
- **Decision:** Canonical column = live **`total`** (numeric).
- **Why:** Renaming a populated column is destructive-class; code references are few
  (`orderService.mapOrder`, `adminService`). Adapt code to read/write `total`.
- **Alternative (needs approval):** `ALTER TABLE orders RENAME COLUMN total TO total_amount`,
  or add a generated column. Both are approval-gated.
- **Data impact:** None if code adapts.

### 3. `orders` additive columns
- **Decision:** ADD `payment_status text default 'pending'`, `note text`,
  `updated_at timestamptz default now()` (+ `set_updated_at` trigger).
- **Why:** Admin flows and `mapOrder` require them; additive and non-destructive.
- **Data impact:** Backfill defaults; safe.

### 4. `profiles` additive columns + role reconciliation
- **Decision:** ADD `full_name text`, `updated_at timestamptz default now()`.
  Role: canonical values **`('customer','admin')`** (matches live default `'customer'`).
- **Why:** `full_name` is written by signup/profile code but absent live → silent data
  loss today. Live already defaults role to `'customer'`, so adopt that vocabulary
  (NOT the repo's `'user'`), then add a `NOT VALID` CHECK after normalizing values.
- **Trade-offs:** Repo/migration `001` used `'user'`; code checks `role === 'admin'`
  for admin only, so `'customer'` vs `'user'` for non-admins is compatible. Any code
  or seed data using `'user'` must be normalized to `'customer'`.
- **Data impact:** Backfill `full_name` from `auth.users.raw_user_meta_data->>'full_name'`
  where available; normalize any non-(`customer`/`admin`) roles. **Needs approval.**

### 5. `products` columns + primary key
- **Decision (additive, non-destructive):** ADD `stock int not null default 0`,
  `discount_price numeric`, and an image strategy (`image_url text` and/or `images jsonb`).
  Rename `"Description"` → `description` (approval-gated; copy data then drop).
- **Decision (approval-gated, High risk):** Change PK from composite `(id, name)` to
  `(id)`. **Requires** verifying `id` is unique first (dedupe check) and re-pointing any
  dependent objects. Until then, FKs from `order_items`/`cart_items` cannot cleanly
  reference `products(id)`.
- **Why:** The app’s catalog, cart pricing, inventory, and `place_order()` all assume
  `stock`/`discount_price`/image fields and a single-column PK.
- **Naming note:** Use snake_case `discount_price` (not `discountPrice`) as canonical;
  the mixed-case identifier `"discountPrice"` in repo `001` requires quoting and is
  error-prone. Frontend must map accordingly.

### 6. `order_items` additive columns + constraints
- **Decision:** ADD `image_url text`, `created_at timestamptz default now()`;
  ADD `CHECK (quantity > 0)`. Keep the live `"Block direct insert order items"` policy.
- **Why:** Receipt rendering needs `image_url`; blocking direct inserts is the correct
  server-authoritative posture (all writes via `place_order()`).

### 7. `cart_items` / `wishlists` integrity + RLS
- **Decision:** Remove the incorrect `DEFAULT gen_random_uuid()` on `user_id`/`product_id`;
  ADD FKs (`user_id`→auth.users, `product_id`→products) and `UNIQUE(user_id, product_id)`;
  ADD owner RLS policies (`FOR ALL USING/ WITH CHECK auth.uid() = user_id`).
- **Why:** Today these tables are deny-all (RLS on, no policy) → cart/wishlist cannot
  work for normal users; and the bad defaults corrupt inserts.
- **Data impact:** Dedupe before adding UNIQUE. **Approval-gated** (constraint add).

### 8. `categories`
- **Decision:** Keep table (canonical). ADD RLS: public `SELECT`, admin write.
  Reconcile product↔category via `products.category_id` FK; treat `products.category`
  (free text) as deprecated/denormalized display value.
- **Why:** Live has both a `categories` table and a `products.category` text column plus
  `category_id`. A single FK-based model is correct; the text column is a migration path.
- **Data impact:** Backfill `category_id` from `category` text (name match). **Approval-gated.**

### 9. Functions (create on live, adapted to canonical schema)
- **Decision:** CREATE `is_admin()`, `handle_new_user()` (+ trigger), and
  `place_order(uuid)` — the latter rewritten to match the canonical schema
  (`orders.total`, `products.stock`/`discount_price`, `order_items` columns, `cart_items`).
- **Why:** Checkout is impossible without `place_order`; admin RLS is cleaner via `is_admin()`.
- **Note:** This is **re-creating known functionality**, not fabricating unknown logic —
  the definitions are derived from repo `001` and adapted to the verified live columns.

### 10. `payments` / `pickup_locations`
- **Decision:** **Defer.** Do not create under a stabilization mandate. Either (a) disable
  the `paymentService` and Admin Pickup Locations code paths, or (b) schedule them as
  explicit Phase 2 features with their own schema design.
- **Why:** No evidence these existed; creating them is feature work, out of scope.

---

## Canonical schema (target, for review)

Summarized target state (snake_case, additive where possible):

- `profiles(id pk→auth.users, email, full_name, phone, role check(customer|admin) default customer, created_at, updated_at)`
- `products(id pk, name, slug, description, price, discount_price, stock default 0, image_url, images jsonb, category, category_id→categories, featured, created_at)`
- `categories(id pk, name, slug, created_at)` + RLS
- `cart_items(id pk, user_id→auth.users, product_id→products, quantity check>0, created_at, unique(user_id,product_id))`
- `wishlists(id pk, user_id→auth.users, product_id→products, created_at, unique(user_id,product_id))`
- `orders(id pk, user_id→auth.users, total, status, payment_status default pending, note, created_at, updated_at)`
- `order_items(id pk, order_id→orders cascade, product_id→products, name, price, quantity check>0, image_url, created_at)`
- Functions: `is_admin()`, `handle_new_user()`+trigger, `place_order(uuid)`.
- RLS on every table (owner scoping + admin), storage policies for `products` bucket.

---

## Items requiring explicit human approval (destructive-class)

1. `products` PK `(id, name)` → `(id)` (dedupe first). **High risk.**
2. Rename `products."Description"` → `description` (copy then drop).
3. `profiles.role` value normalization + CHECK.
4. `cart_items`/`wishlists` `UNIQUE` constraints (dedupe first).
5. Any table/column RENAME if Path B is chosen over adapting code.
6. Whether to create `payments`/`pickup_locations` (feature decision).

## Unverifiable without live access beyond schema

- Storage bucket `products` existence + visibility (data-level).
- Auth settings (password policy, email confirmation, captcha).
- Row counts / whether `products.id` is already unique (needed before PK change).
