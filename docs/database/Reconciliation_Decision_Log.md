# Reconciliation Decision Log — Babees Place

**Status:** Authoritative decision record for Phase 1.6 Workstream B.
**Date:** 2026-07-12
**Companion:** `Final_Canonical_Schema.md` (the resulting design). Cross-references `ADR-001`.
**Rules honored:** analysis only — no migrations, SQL, live/frontend changes, or commits.
**Decision vocabulary:** `KEEP LIVE` · `ADOPT REPOSITORY` · `CREATE NEW CANONICAL`.

Every schema difference identified in `Schema_Comparison_Matrix.md` has an explicit decision
below. Where evidence is insufficient, the item is listed under **Unresolved Questions**
rather than guessed.

---

## Section 1 — Object-by-object decision table (Workstream A)

**Tables**

| ID | Object | Live definition | Repository definition | Canonical decision | Reason | Frontend impact | Data mig | Risk | Priority |
|---|---|---|---|---|---|---|---|---|---|
| D-TBL-1 | `profiles` | id,email,role(cust),phone,created_at | +full_name,updated_at, role CHECK(user/admin) | **KEEP LIVE + additive** | Live is SoT; add app-needed cols | none (cols already written) | Yes (backfill full_name) | Med | High |
| D-TBL-2 | `categories` | id,name,slug,created_at | (absent in 001) | **KEEP LIVE** | Table exists; resolves category model | adopt for admin CRUD | No | Low | High |
| D-TBL-3 | `products` | composite PK, `"Description"`, no stock/discount/img | id PK, stock, discountPrice, images | **CREATE NEW CANONICAL** | Neither matches; app needs restructure | map new cols (snake_case) | Yes | High | High |
| D-TBL-4 | `cart_items` | cart_items, no FK/unique | `cart`, FK+unique | **KEEP LIVE name + integrity** | Rename destructive; adapt code | `.from('cart')`→`cart_items` | No (dedupe for unique) | Med | High |
| D-TBL-5 | `wishlists` | wishlists, no FK/unique | `wishlist` | **KEEP LIVE name + integrity** | Same as cart | `.from('wishlist')`→`wishlists` + realtime | No (dedupe) | Med | High |
| D-TBL-6 | `orders` | total,status, no payment/updated | total_amount, payment_status,note | **KEEP LIVE + additive** | Keep `total` (rename destructive); add cols | `total_amount`→`total`; use new cols | Backfill defaults | Med | High |
| D-TBL-7 | `order_items` | no image_url/created_at, INSERT blocked | +image_url, insert-own | **KEEP LIVE + additive** | Keep blocking policy (safer); add snapshot cols | receipt image mapping | No | Low | High |

**Enum / Types**

| ID | Object | Live | Repo | Canonical decision | Reason | Data mig | Risk | Priority |
|---|---|---|---|---|---|---|---|---|
| D-ENUM-1 | `order_status` enum (pending,paid,fulfilled,cancelled) | present but **unused** (orders.status is text) | n/a | **CREATE NEW CANONICAL: drop enum, use `text` + CHECK** | Enum values don't match frontend vocabulary; text+CHECK is easier to evolve | No | Low | Med |

**Primary keys / Foreign keys / Constraints / Indexes**

| ID | Object | Live | Canonical decision | Reason | Data mig | Risk | Priority |
|---|---|---|---|---|---|---|---|
| D-KEY-1 | products PK | composite `(id,name)` | **CREATE NEW: PK `(id)`** | Composite blocks FKs + single-row guarantees | Verify id uniqueness first | High | High |
| D-KEY-2 | FKs (orders.user_id, cart_items.*, order_items.product_id, wishlists.*) | **absent** | **ADOPT REPOSITORY (add FKs)** | Referential integrity | Verify orphans | Med | High |
| D-KEY-3 | UNIQUE(user_id,product_id) on cart_items/wishlists | absent | **ADOPT REPOSITORY (add)** | Upsert correctness | Dedupe first | Med | High |
| D-KEY-4 | CHECK(quantity>0) | absent | **ADOPT REPOSITORY (add)** | Data validity | Verify | Low | Med |
| D-KEY-5 | bad defaults (`gen_random_uuid()` on FK cols; `phone='+254...'`) | present | **CREATE NEW: remove** | Corrupts inserts / misleading | No | Low | Med |
| D-IDX-1 | indexes (orders,order_items,cart_items,products) | none | **ADOPT REPOSITORY (add)** | Performance | No | Low | Med |

**RLS policies**

| ID | Object | Live | Canonical decision | Reason | Risk | Priority |
|---|---|---|---|---|---|---|
| D-RLS-1 | profiles UPDATE | USING only, **no WITH CHECK** | **CREATE NEW: add WITH CHECK (role unchanged) + admin policy** | Closes C-1 role escalation | Low | **Critical** |
| D-RLS-2 | cart_items/wishlists/categories | RLS on, **no policies (deny-all)** | **ADOPT REPOSITORY: add owner/public policies** | Tables unusable today | Med | High |
| D-RLS-3 | products write | public SELECT only | **CREATE NEW: add admin write policy** | Admin catalog mgmt fails | Med | High |
| D-RLS-4 | orders insert / order_items insert | orders owner-insert; order_items blocked | **KEEP LIVE (blocked) + remove orders direct insert** | Force server-authoritative `place_order` | Low | High |

**RPC functions & Storage**

| ID | Object | Live | Canonical decision | Reason | Priority |
|---|---|---|---|---|---|
| D-RPC-1 | `is_admin()` | absent | **ADOPT REPOSITORY (create)** | Central admin check for RLS | High |
| D-RPC-2 | `handle_new_user()`+trigger | absent | **ADOPT REPOSITORY (create)** | Auto profile creation | High |
| D-RPC-3 | `place_order()` | absent | **CREATE NEW CANONICAL (adapt 001 to live cols)** | Server-side totals + stock lock; checkout depends | **Critical** |
| D-RPC-4 | `cancel_order()` | absent | **CREATE NEW (Phase 2)** | Atomic cancel + stock restore | Med |
| D-STOR-1 | `products` bucket + object policies | no user policies; bucket unverified | **CREATE NEW: add policies (public read/admin write)** | Image upload security | High |

> Full field-level `products` and per-column decisions are enumerated in Sections 2–3.

---

## Section 2 — Product Domain Review (Workstream B)

For each field: decision + reason. Live `products` = `id,name,slug,price,category,category_id,featured,created_at,"Description"`.

| ID | Field | Decision | Reason |
|---|---|---|---|
| D-PROD-1 | `stock` | **ADD** | Inventory screens, low-stock, and `place_order` stock checks all require it. Absent live → those features are broken. |
| D-PROD-2 | `image_url` | **ADD** | `CartContext.getItemImage` and product cards read a primary image; none exists live. |
| D-PROD-3 | `images` (jsonb) | **ADD** | Frontend reads `product.images` (gallery, `isPrimary`). Keep as jsonb now; promote to a `product_images` table later if needed. |
| D-PROD-4 | `category_id` | **KEEP + make FK** | Live has the column; canonical makes it the FK source of truth to `categories`. |
| D-PROD-5 | `category` (text) | **DEPRECATE (keep transitional)** | Denormalized duplicate of category_id; `productService.getCategories` derives from it today. Backfill `category_id`, then drop text in a gated step. |
| D-PROD-6 | `discount_price` | **ADD (snake_case)** | Cart pricing (`getItemPrice`) and `place_order` use a discounted price. Canonical name `discount_price` (not `"discountPrice"`). |
| D-PROD-7 | `created_at` | **KEEP LIVE** | Exists; standardize type to `timestamptz`. |
| D-PROD-8 | `updated_at` | **ADD + trigger** | Needed for change tracking/cache invalidation; absent live. |
| D-PROD-9 | `slug` | **KEEP LIVE** | Used by `productService.getProduct` slug fallback. Add UNIQUE. |
| D-PROD-10 | `featured` | **KEEP LIVE** | Exists; used for merchandising. |
| D-PROD-11 | `is_active` (`active`) | **ADD (recommended, not blocking)** | Common need to hide products without deleting. **Caveat:** no current frontend reference found → introduce with app support, do not assume existing behavior. |
| D-PROD-12 | `description` | **RENAME** from `"Description"` | Capitalized/quoted identifier is error-prone; canonical snake_case. |
| D-PROD-13 | PK `(id,name)` → `(id)` | **CHANGE (gated)** | See D-KEY-1. |

**Fields that should NOT exist (now):** `rating`/`soldCount` (referenced only by a dead
`SORT_OPTIONS` constant, no live column, no read path) — **do not add** without a real
feature; `views`, `tags` — no evidence.

---

## Section 3 — Customer Domain Review (Workstream C)

| ID | Topic | Decision | Reason / Alternatives |
|---|---|---|---|
| D-CUST-1 | `profiles.role` vocabulary | **KEEP LIVE: `customer` / `admin`** | Live default is `customer`; `AuthContext` only branches on `=== 'admin'`. Repo/`constants.js` use `user` — **update the frontend constant** to `customer`. Alt (adopt `user`) rejected: would require touching live data. |
| D-CUST-2 | `profiles.full_name` | **ADD** | Written by signup/profile/admin code; missing live → silent loss. |
| D-CUST-3 | `phone` | **KEEP LIVE (text)**; app normalizes via `normalizePhone` | Alt (dedicated E.164 type / validation) deferred; text + app normalization is sufficient. Remove misleading literal default. |
| D-CUST-4 | Addresses | **DEFER**; interim `orders.delivery_address text` | `userService.addresses` calls a non-existent table. A full `addresses` entity is Phase 2+. For delivery in Phase 2, a text field on the order suffices. |
| D-CUST-5 | Order totals | **KEEP LIVE `total`**, computed server-side in `place_order` | Renaming to `total_amount` is destructive; adapt code. Server computes from live prices (never trust client). |
| D-CUST-6 | Order status vocabulary | **CHECK IN (pending,processing,shipped,delivered,cancelled)** | Evidence: `constants.js` `ORDER_STATUSES`. Payment status separate: (pending,paid,failed,refunded). |
| D-CUST-7 | Timestamps | **`timestamptz`, `created_at`/`updated_at` + triggers** | Live mixes `timestamp` (no tz) and hard-coded defaults; standardize. |
| D-CUST-8 | Soft deletes | **Do NOT add generalized soft-delete**; use `products.is_active` for hiding; never hard-delete `orders` | No evidence of a soft-delete requirement elsewhere; avoid speculative columns. Orders are historical records (retain). |
| D-CUST-9 | Cart canonical | **`cart_items`** + FKs + `UNIQUE` + `CHECK(qty>0)` + owner RLS | See D-TBL-4, D-KEY-*. |
| D-CUST-10 | Wishlist canonical | **`wishlists`** + FKs + `UNIQUE` + owner RLS | See D-TBL-5. |

---

## Section 4 — Commerce Features (Workstream D)

| ID | Feature | Classification | Reasoning |
|---|---|---|---|
| D-FEAT-1 | Payments | **Required for Phase 2** | Real checkout (M‑Pesa) is core. Evidence: `paymentService`, `orders.mpesa_receipt_number` read by `mapOrder`. Design a `payments` table; interim `orders.payment_status`/`mpesa_receipt_number`. |
| D-FEAT-2 | Pickup locations | **Required for Phase 2** | Evidence: `AdminPickupLocations` page, `DELIVERY_TYPES.pickup`, `mapOrder.pickup_location`. Design `pickup_locations` table; interim `orders.pickup_location` text. |
| D-FEAT-3 | Shipping addresses | **Required for Phase 2 (minimal)** | `DELIVERY_TYPES.delivery` + `mapOrder.delivery_address`. Start with `orders.delivery_address` text; full `addresses` table deferred (D-CUST-4). |
| D-FEAT-4 | Coupons / discounts | **Not required** | No evidence anywhere in code or live. Product-level `discount_price` covers current discounting. |
| D-FEAT-5 | Inventory reservations | **Deferred** | `place_order` with `FOR UPDATE` row locking prevents oversell for MVP scale; a reservation subsystem is premature. |
| D-FEAT-6 | Audit logging | **Deferred** | Good practice but not an MVP blocker; revisit when admin actions grow. |

---

## Section 5 — RPC Strategy (Workstream E)

| ID | Function | Purpose | Arguments | Returns | Security model | RPC preferable? |
|---|---|---|---|---|---|---|
| D-RPC-1 | `is_admin()` | Central admin check for RLS | none (uses `auth.uid()`) | boolean | SECURITY DEFINER, `search_path` pinned, STABLE | **Yes** — avoids recursive RLS and duplicated role checks |
| D-RPC-2 | `handle_new_user()` | Auto-create `profiles` on signup | trigger `NEW` | trigger | SECURITY DEFINER | **Yes** — must run with elevated rights on `auth.users` insert |
| D-RPC-3 | `place_order()` | Atomic checkout | `p_user_id uuid default auth.uid()` | `uuid` (order id) | SECURITY DEFINER; caller check `auth.uid()=p_user_id OR is_admin()`; `FOR UPDATE` locks | **Yes** — server computes totals from live prices, prevents forged totals + oversell; the only way to write orders/order_items |
| D-RPC-4 | `cancel_order()` | Cancel + restore stock | `p_order_id uuid` | void/boolean | SECURITY DEFINER; owner or admin | **Yes (Phase 2)** — multi-step atomic (status + stock) |
| D-RPC-5 | `reserve_inventory()` / `restore_inventory()` | Hold/return stock | tbd | tbd | SECURITY DEFINER | **Deferred** — not needed while `place_order` locks rows; adopt only with a cart-hold/reservation UX |

None implemented in this workstream (rules). Definitions are derived from repo `001` +
verified live columns — no fabricated logic.

---

## Section 6 — Final Validation

**Coverage check:** every difference in `Schema_Comparison_Matrix.md` maps to a decision ID
above (tables D-TBL-1..7, enum D-ENUM-1, keys/constraints/indexes D-KEY/D-IDX, RLS D-RLS-1..4,
RPC D-RPC-1..5, storage D-STOR-1, product fields D-PROD-1..13, customer topics D-CUST-1..10,
features D-FEAT-1..6). No difference is left undecided.

**Tally**

| Metric | Count | Items |
|---|---:|---|
| Total objects reviewed | **33** | 7 tables + 1 enum + 13 product fields + 4 RLS groups + 5 RPCs + 1 storage + 2 key/index groups (aggregated) |
| Kept from live | 5 tables + policies | profiles, categories, orders, order_items base + `order_items` INSERT-blocked policy + `orders.total` name |
| Adopted from repository | FKs, UNIQUE, CHECKs, indexes, `is_admin`/`handle_new_user`/`place_order` definitions, RLS `WITH CHECK` pattern | |
| New canonical objects | `products` (restructured), added columns (profiles/orders/order_items/products), `cart_items`/`wishlists` integrity, `cancel_order`, storage policies, text+CHECK for status | |
| Deferred objects | 4 | `addresses`, `pickup_locations` table, `payments` table (Phase 2), reservations/audit (later) |
| Not required | 2 | coupons; generalized soft-delete |

**Unresolved questions (require human/dashboard evidence — not guessed):**
1. Is `products.id` already unique? (Blocks D-KEY-1 PK change.) → `SELECT id,count(*) FROM products GROUP BY id HAVING count(*)>1;`
2. Does the `products` storage bucket exist and is it public? → dashboard / `storage.buckets`.
3. Are there duplicate `(user_id,product_id)` rows in `cart_items`/`wishlists`? (Blocks D-KEY-3.)
4. Should the frontend role constant become `customer` (D-CUST-1) — confirm no other code depends on `'user'`.
5. Payments provider/flow (M‑Pesa Daraja?) — determines `payments` table shape (D-FEAT-1) — product decision.

**Cross-reference:** All decisions operate under `ADR-001` (adopt live as source of truth;
additive-first; destructive/normalizing steps gated on approval + backup). Execution belongs
to the reconciliation phase and is **not** performed here.

**Stop:** Phase 1.6 Workstream B complete. Canonical schema finalized; every difference has an
explicit decision. No migrations, SQL, live/frontend changes, or commits were made.
