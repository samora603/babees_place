# Final Canonical Production Schema — Babees Place

**Status:** AUTHORITATIVE database design (Phase 1.6 Workstream B output).
**Date:** 2026-07-12
**Basis:** live baseline (`docs/database/generated_baseline/001_initial_schema.sql`),
`Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`,
`Frontend_Database_Compatibility.md`, `Migration_Strategy.md`, `ADR-001`,
`Phase1_5_Readiness_Report.md`, and evidence from `frontend/src/utils/constants.js`.
**Constraints honored:** No migrations, no SQL execution, no live/frontend changes. This is
a specification, not an implementation. Every object has an explicit decision in
`Reconciliation_Decision_Log.md`.

> Canonical values verified from `constants.js`:
> order status ∈ {pending, processing, shipped, delivered, cancelled};
> payment status ∈ {pending, paid, failed, refunded}; delivery type ∈ {pickup, delivery};
> role ∈ {customer, admin} (adopting the live default `customer`).

---

## 1. Entity overview

Phase‑1 (stabilization) canonical entities — **7 core tables** (all exist live; reconciled):

| Entity | Purpose | Origin decision |
|---|---|---|
| `profiles` | 1:1 with `auth.users`; identity, role, contact | KEEP LIVE + additive |
| `categories` | Product categorization | KEEP LIVE + RLS |
| `products` | Catalog items | CREATE NEW CANONICAL (restructured) |
| `cart_items` | Per-user cart lines | KEEP LIVE (name) + integrity |
| `wishlists` | Per-user saved products | KEEP LIVE (name) + integrity |
| `orders` | Order header + totals/status | KEEP LIVE + additive |
| `order_items` | Order line snapshots | KEEP LIVE + additive |

Phase‑2 (deferred, designed here as extension points only): `payments`, `pickup_locations`,
optionally `addresses`. Explicitly out of scope: `coupons`, `inventory_reservations`,
`audit_log` (see Decision Log D‑FEAT‑*).

## 2. Relationship overview

```
auth.users 1─1 profiles
auth.users 1─* orders            (orders.user_id)
auth.users 1─* cart_items        (cart_items.user_id)
auth.users 1─* wishlists         (wishlists.user_id)
categories 1─* products          (products.category_id)
products   1─* cart_items        (cart_items.product_id)
products   1─* wishlists         (wishlists.product_id)
products   1─* order_items       (order_items.product_id, ON DELETE SET NULL)
orders     1─* order_items       (order_items.order_id, ON DELETE CASCADE)
```

## 3. Naming conventions

- **snake_case** for all identifiers (tables and columns). Fix live `products."Description"` → `description`; canonical price field is `discount_price` (not `"discountPrice"`).
- **Plural** table names for entities (`products`, `orders`, `cart_items`, `wishlists`).
- Primary key: `id uuid default gen_random_uuid()`.
- Foreign keys: `<referenced_entity_singular>_id` (e.g., `product_id`, `order_id`, `category_id`, `user_id`).
- Timestamps: `timestamptz`, `created_at default now()`, `updated_at default now()` (maintained by trigger).
- Money: `numeric(12,2)`.
- Booleans: positive names (`is_active`, `featured`).
- Enumerated text via `CHECK` constraints (not PG `enum` types — easier to evolve; see D‑ENUM‑1).

## 4. Table specifications

### 4.1 `profiles`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | — | PK, FK→auth.users(id) ON DELETE CASCADE |
| email | text | yes | — | |
| full_name | text | yes | — | **ADD** (frontend writes it) |
| phone | text | yes | — | drop live literal default `'+254...'` |
| role | text | no | `'customer'` | CHECK (role IN ('customer','admin')) |
| created_at | timestamptz | no | now() | |
| updated_at | timestamptz | no | now() | **ADD** + trigger |

### 4.2 `categories`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | PK |
| name | text | no | — | |
| slug | text | yes | — | UNIQUE recommended |
| created_at | timestamptz | no | now() | (live has no default) |

### 4.3 `products` (CREATE NEW CANONICAL)
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | **PK `(id)`** (change from composite `(id,name)` — gated) |
| name | text | no | — | |
| slug | text | yes | — | UNIQUE recommended (used by `productService.getProduct`) |
| description | text | yes | — | **rename** from `"Description"` |
| price | numeric(12,2) | no | 0 | |
| discount_price | numeric(12,2) | yes | — | **ADD** (cart pricing / place_order) |
| stock | integer | no | 0 | **ADD** (inventory / checkout) |
| image_url | text | yes | — | **ADD** (primary image) |
| images | jsonb | no | `'[]'` | **ADD** (gallery; `[{url,isPrimary}]`) |
| category_id | uuid | yes | — | FK→categories(id) ON DELETE SET NULL |
| category | text | yes | — | **DEPRECATED** (transitional; drop after backfill) |
| featured | boolean | no | false | KEEP LIVE |
| is_active | boolean | no | true | **ADD (recommended)** — soft-hide; limited current frontend evidence (see D‑PROD‑9) |
| created_at | timestamptz | no | now() | |
| updated_at | timestamptz | no | now() | **ADD** + trigger |

### 4.4 `cart_items`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | PK |
| user_id | uuid | no | — | FK→auth.users(id) CASCADE; **drop** bad `gen_random_uuid()` default |
| product_id | uuid | no | — | FK→products(id) CASCADE; **drop** bad default |
| quantity | integer | no | 1 | CHECK (quantity > 0) |
| created_at | timestamptz | no | now() | |
| — | — | — | — | **UNIQUE (user_id, product_id)** |

### 4.5 `wishlists`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | PK |
| user_id | uuid | no | — | FK→auth.users(id) CASCADE |
| product_id | uuid | no | — | FK→products(id) CASCADE |
| created_at | timestamptz | no | now() | |
| — | — | — | — | **UNIQUE (user_id, product_id)** |

### 4.6 `orders`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | PK |
| user_id | uuid | no | — | FK→auth.users(id) CASCADE (**add FK**) |
| total | numeric(12,2) | no | 0 | KEEP LIVE name `total` (server-computed) |
| status | text | no | `'pending'` | CHECK IN (pending,processing,shipped,delivered,cancelled) |
| payment_status | text | no | `'pending'` | **ADD**; CHECK IN (pending,paid,failed,refunded) |
| note | text | yes | — | **ADD** |
| delivery_type | text | yes | — | **ADD (Phase 2)**; CHECK IN (pickup,delivery) |
| pickup_location | text | yes | — | **ADD (Phase 2)** (or FK→pickup_locations later) |
| delivery_address | text | yes | — | **ADD (Phase 2)** |
| mpesa_receipt_number | text | yes | — | **ADD (Phase 2)** (read by `mapOrder`) |
| created_at | timestamptz | no | now() | |
| updated_at | timestamptz | no | now() | **ADD** + trigger |

### 4.7 `order_items`
| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| id | uuid | no | gen_random_uuid() | PK |
| order_id | uuid | no | — | FK→orders(id) ON DELETE CASCADE |
| product_id | uuid | yes | — | FK→products(id) ON DELETE SET NULL (**add FK**) |
| name | text | no | — | snapshot |
| price | numeric(12,2) | no | — | snapshot |
| quantity | integer | no | — | CHECK (quantity > 0) |
| image_url | text | yes | — | **ADD** snapshot |
| created_at | timestamptz | no | now() | **ADD** |

## 5. Required indexes
- `products (category_id)`, `products (is_active)`, `products (slug)` UNIQUE.
- `products` full-text: `to_tsvector('simple', name || ' ' || coalesce(description,''))` GIN (search).
- `orders (user_id)`, `orders (created_at DESC)`, `orders (status)`.
- `order_items (order_id)`, `order_items (product_id)`.
- `cart_items (product_id)` (composite UNIQUE already covers `user_id`).
- `wishlists (product_id)`.

## 6. Required constraints
- PKs on every table; `products` PK → `(id)` (gated on dedupe).
- FKs per §2 (all currently missing on live except `order_items.order_id`, `profiles.id`).
- `UNIQUE(user_id, product_id)` on `cart_items`, `wishlists`.
- `CHECK (quantity > 0)` on `cart_items`, `order_items`.
- `CHECK` on `profiles.role`, `orders.status`, `orders.payment_status`, `orders.delivery_type`.
- Remove erroneous live defaults (`gen_random_uuid()` on FK columns, literal `phone` default).

## 7. Required RLS policies
| Table | Policy | Rule |
|---|---|---|
| profiles | select | `auth.uid() = id OR is_admin()` |
| profiles | update own | `USING auth.uid()=id` **`WITH CHECK auth.uid()=id AND role unchanged`** |
| profiles | update admin | `is_admin()` (role changes) |
| profiles | insert own | `WITH CHECK auth.uid()=id` |
| categories | select | `true` (public) |
| categories | write | `is_admin()` |
| products | select | `true` (optionally `is_active OR is_admin()`) |
| products | write | `is_admin()` |
| cart_items | all own | `USING/CHECK auth.uid()=user_id` |
| wishlists | all own | `USING/CHECK auth.uid()=user_id` |
| orders | select | `auth.uid()=user_id OR is_admin()` |
| orders | update admin | `is_admin()` |
| orders | (no direct INSERT) | creation only via `place_order()` |
| order_items | select | via parent order ownership/admin |
| order_items | insert | **blocked** (`WITH CHECK (false)`) — writes only via `place_order()` |

## 8. Required RPCs (specified, NOT implemented)
- `is_admin() → boolean` — SECURITY DEFINER; reads `profiles.role`.
- `handle_new_user()` (trigger fn) — autocreate `profiles` row on signup, role `customer`.
- `place_order(p_user_id uuid default auth.uid()) → uuid` — SECURITY DEFINER; validates stock with `FOR UPDATE`, computes `total` from live prices, inserts order + items, decrements stock, clears cart.
- `cancel_order(p_order_id uuid) → void` — SECURITY DEFINER; owner/admin only; sets status `cancelled`, restores stock. **Phase 2.**
- (Deferred) `reserve_inventory()` / `restore_inventory()` — only if a reservation model is adopted; `place_order` row-locking suffices for MVP.

## 9. Required triggers
- `on_auth_user_created` AFTER INSERT ON `auth.users` → `handle_new_user()`.
- `set_updated_at` BEFORE UPDATE ON `profiles`, `products`, `orders` → `set_updated_at()`.

## 10. Storage
- Bucket `products` (verify existence — dashboard). Policies on `storage.objects`: public read
  for `products`; write restricted to `is_admin()`. (No user-defined storage policies exist on
  live today.)

## 11. Future extension points
- `payments` table (M‑Pesa/Stripe) — Phase 2; `orders.mpesa_receipt_number` is an interim link.
- `pickup_locations` table — Phase 2; `orders.pickup_location` text is interim.
- `addresses` table — later; `orders.delivery_address` text is interim.
- `coupons`, `inventory_reservations`, `audit_log` — not required now (see Decision Log).
- Convert product `images jsonb` → dedicated `product_images` table if gallery grows complex.
