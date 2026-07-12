# Schema Comparison Matrix — Live vs Repository

**Date:** 2026-07-12
**Live project:** `qfcygrxrfszcdltangec` ("Babis-place")
**Method:** read-only `supabase db dump --linked -s public` and `-s storage`; repository migration `001_schema_rls_place_order.sql` and frontend source.
**Rule compliance:** No database modifications were made. Where evidence is data-only (e.g., storage bucket rows) it is explicitly marked *not verifiable from a schema dump*.

Legend — **Canonical** = recommended source of truth: `LIVE` (keep live), `REPO` (adopt repo/code intent), `MERGE` (combine). **Mig** = schema migration required. **Data** = data migration required. **Risk** = Low/Med/High.

---

## 1. Tables

| Table (repo/code) | Table (live) | Match? | Canonical | Reason | Mig | Data | Risk |
|---|---|---|---|---|---|---|---|
| `cart` | `cart_items` | ❌ name | **LIVE** (`cart_items`) + code change | Live is source of truth; renaming a live table needs approval, changing code is cheaper/safer | No (if code adapts) / Yes (if rename) | No | Low–Med |
| `wishlist` | `wishlists` | ❌ name | **LIVE** (`wishlists`) + code change | Same as above | No / Yes | No | Low–Med |
| `products` | `products` | 🟡 columns | **MERGE** | Keep table; add missing columns app needs | Yes | Maybe | Med |
| `orders` | `orders` | 🟡 columns | **MERGE** | Keep; reconcile `total` vs `total_amount`, add `payment_status`/`updated_at` | Yes | Maybe | Med |
| `order_items` | `order_items` | 🟡 columns/policy | **MERGE** | Add `image_url`/`created_at`; keep INSERT-blocked policy (good) | Yes | No | Med |
| `profiles` | `profiles` | 🟡 columns | **MERGE** | Add `full_name`, `updated_at`; reconcile `role` default/CHECK | Yes | Maybe | Med |
| `categories` | `categories` | ✅ exists | **LIVE** | Table exists live; resolves the "categories model" question | No | No | Low |
| `payments` | — (absent) | ❌ missing | **DECISION** | Code stub references it; only add if payments feature is in scope | Yes (if kept) | No | Med |
| `pickup_locations` | — (absent) | ❌ missing | **DECISION** | Admin UI references it; add only if feature in scope | Yes (if kept) | No | Med |

---

## 2. Columns (by table)

### `products`
| Column | Repo/code expects | Live | Match? | Canonical | Mig | Data | Risk |
|---|---|---|---|---|---|---|---|
| `id` | uuid PK | uuid, part of composite PK `(id, name)` | 🟡 | **MERGE** → PK `(id)` | Yes | Verify dupes | High |
| `name` | text | text NOT NULL (in PK) | 🟡 | LIVE | — | — | Med |
| `slug` | text | text | ✅ | LIVE | No | No | Low |
| `price` | numeric | numeric | ✅ | LIVE | No | No | Low |
| `category` | text (filter/getCategories) | text | ✅ | see Categories model | No | No | Low |
| `category_id` | (admin) uuid | uuid | ✅ | MERGE (FK) | Yes (FK) | Maybe | Med |
| `featured` | (implied) | boolean default false | ✅ | LIVE | No | No | Low |
| `description` | `Description`? code uses none directly; UI shows description | **`"Description"`** (capital D) | ❌ | **REPO** → rename to `description` | Yes | Yes (copy) | Med |
| `stock` | **required** (inventory, place_order, low-stock) | **absent** | ❌ | **REPO** → add `stock int` | Yes | Backfill 0 | Med |
| `discountPrice` | used (cart pricing, place_order) | **absent** | ❌ | **REPO** → add (`discount_price`) | Yes | No | Med |
| `image_url` / `images` | used (product cards, cart image) | **absent** | ❌ | **REPO** → add image storage strategy | Yes | Yes | Med |
| `created_at` | — | timestamp (no tz) | ✅ | LIVE (consider `timestamptz`) | Opt | No | Low |

### `orders`
| Column | Repo/code expects | Live | Match? | Canonical | Mig | Data | Risk |
|---|---|---|---|---|---|---|---|
| `id` | uuid PK | uuid PK | ✅ | LIVE | No | No | Low |
| `user_id` | uuid → auth.users | uuid (no FK shown) | 🟡 | MERGE (add FK) | Yes | Verify | Med |
| total | **`total_amount`** | **`total`** | ❌ | **DECISION** (recommend keep `total`, adapt code) | Yes/No | No | Med |
| `status` | text | text default 'pending' | ✅ | LIVE (+ CHECK) | Opt | No | Low |
| `payment_status` | used (admin, mapOrder) | **absent** | ❌ | **REPO** → add | Yes | Backfill | Med |
| `note` | used (admin) | **absent** | ❌ | **REPO** → add | Yes | No | Low |
| `updated_at` | used (admin update) | **absent** | ❌ | **REPO** → add + trigger | Yes | No | Low |
| `created_at` | used | timestamp (no tz) | ✅ | LIVE | Opt | No | Low |

### `order_items`
| Column | Repo/code expects | Live | Match? | Canonical | Mig | Data | Risk |
|---|---|---|---|---|---|---|---|
| `id` | uuid PK | uuid PK | ✅ | LIVE | No | No | Low |
| `order_id` | uuid → orders (CASCADE) | uuid FK → orders CASCADE | ✅ | LIVE | No | No | Low |
| `product_id` | uuid → products | uuid (no FK) | 🟡 | MERGE (add FK after products PK fix) | Yes | Verify | Med |
| `name` | text | text default '' | ✅ | LIVE | No | No | Low |
| `price` | numeric | numeric | ✅ | LIVE | No | No | Low |
| `quantity` | int CHECK>0 | smallint (no CHECK) | 🟡 | MERGE (add CHECK) | Yes | Verify | Low |
| `image_url` | used (receipt) | **absent** | ❌ | REPO → add | Yes | No | Low |
| `created_at` | used | **absent** | ❌ | REPO → add | Yes | No | Low |

### `profiles`
| Column | Repo/code expects | Live | Match? | Canonical | Mig | Data | Risk |
|---|---|---|---|---|---|---|---|
| `id` | uuid PK → auth.users CASCADE | uuid PK, FK → auth.users CASCADE | ✅ | LIVE | No | No | Low |
| `email` | text | text | ✅ | LIVE | No | No | Low |
| `full_name` | **written by code** | **absent** | ❌ | **REPO** → add | Yes | Backfill from auth metadata | Med |
| `phone` | text | text default '+254...' | 🟡 | LIVE (fix odd default) | Opt | No | Low |
| `role` | `'user'`/`'admin'` + CHECK | text default **`'customer'`**, no CHECK | ❌ | **DECISION** (`customer`+`admin`) | Yes | Normalize values | Med |
| `created_at` | — | timestamptz | ✅ | LIVE | No | No | Low |
| `updated_at` | used | **absent** | ❌ | REPO → add + trigger | Yes | No | Low |

### `cart_items` (live) vs `cart` (code)
| Column | Code expects (on `cart`) | Live (`cart_items`) | Match? | Canonical | Risk |
|---|---|---|---|---|---|
| `id` | uuid PK | uuid PK | ✅ | LIVE | Low |
| `user_id` | uuid → auth.users | uuid (default gen_random_uuid!, no FK) | 🟡 | MERGE (drop bad default, add FK) | Med |
| `product_id` | uuid → products CASCADE | uuid (no FK) | 🟡 | MERGE (add FK) | Med |
| `quantity` | int default 1 CHECK>0 | smallint default 1 | 🟡 | MERGE (add CHECK) | Low |
| UNIQUE(user_id,product_id) | required (upsert logic) | **absent** | ❌ | REPO → add UNIQUE | Yes/dupe-check | Med |
| `created_at` | timestamptz | timestamp (no tz) | 🟡 | LIVE | Low |

### `wishlists` (live) vs `wishlist` (code)
| Column | Code expects | Live | Match? | Canonical | Risk |
|---|---|---|---|---|---|
| `id`/`user_id`/`product_id`/`created_at` | — | present | 🟡 name only | LIVE (`wishlists`) | Low |
| UNIQUE(user_id,product_id) | implied | absent | ❌ | REPO → add | Low |

---

## 3. Primary Keys
| Table | Repo | Live | Canonical | Risk |
|---|---|---|---|---|
| products | `(id)` | **`(id, name)`** | REPO `(id)` — composite PK breaks normal FK refs & upserts | High (needs dupe check) |
| all others | `(id)` | `(id)` | LIVE | Low |

## 4. Foreign Keys
| FK | Repo | Live | Canonical | Mig | Risk |
|---|---|---|---|---|---|
| order_items.order_id → orders.id | CASCADE | **present** CASCADE | LIVE | No | Low |
| profiles.id → auth.users.id | CASCADE | **present** CASCADE | LIVE | No | Low |
| orders.user_id → auth.users.id | CASCADE | **absent** | REPO (add) | Yes | Med |
| cart(_items).product_id → products.id | CASCADE | **absent** | REPO (add) | Yes | Med |
| cart(_items).user_id → auth.users.id | present | **absent** | REPO (add) | Yes | Med |
| order_items.product_id → products.id | present | **absent** | REPO (add) | Yes | Med |
| wishlists.* FKs | present | **absent** | REPO (add) | Yes | Med |

## 5. Constraints (CHECK / UNIQUE / defaults)
| Constraint | Repo | Live | Canonical | Risk |
|---|---|---|---|---|
| profiles.role CHECK | `IN ('user','admin')` | **none** | DECISION `IN ('customer','admin')` | Med |
| orders.status CHECK | none (proposed 003) | none | REPO add (`NOT VALID`) | Low |
| quantity > 0 | present | none | REPO add | Low |
| cart UNIQUE(user,product) | present | none | REPO add | Med |
| odd defaults (`gen_random_uuid()` on FK cols, `phone='+254...'`, hard-coded timestamp defaults) | n/a | **present on live** | REPO (remove bad defaults) | Med |

## 6. Indexes
| Index | Repo (003 proposed) | Live | Canonical | Risk |
|---|---|---|---|---|
| PK indexes | implicit | implicit | LIVE | Low |
| orders(user_id), orders(created_at), order_items(order_id), (product_id), cart(product_id) | proposed | **none** | REPO add | Low |
| products search (FTS) | proposed (deferred) | none | REPO add later | Low |

## 7. Triggers
| Trigger | Repo (001/003) | Live | Canonical | Risk |
|---|---|---|---|---|
| `on_auth_user_created` (profiles autocreate) | defined | **absent** | REPO add | Med |
| `set_updated_at` (orders/profiles) | defined (003) | **absent** | REPO add (after cols added) | Low |

## 8. Functions
| Function | Repo (001) | Live | Canonical | Risk |
|---|---|---|---|---|
| `place_order(uuid)` | defined | **absent** | REPO add (adapted to live schema) | High (checkout depends) |
| `is_admin()` | defined | **absent** | REPO add | Med |
| `handle_new_user()` | defined | **absent** | REPO add | Med |

## 9. Views
| View | Repo | Live | Notes |
|---|---|---|---|
| (none) | none | none found | No views on either side |

## 10. RLS Policies
| Table | Repo (001/002) | Live | Canonical | Risk |
|---|---|---|---|---|
| profiles | select/update own (002 adds WITH CHECK + admin) | select/insert/update own — **UPDATE has USING, no WITH CHECK** | REPO (add WITH CHECK) | **High (C-1 live)** |
| orders | select own/admin, insert own, admin update | "Users view/insert own", "Admins view/update" | LIVE (equivalent) | Low |
| order_items | select via order; insert own | "Users view own", **"Block direct insert" WITH CHECK(false)** | LIVE (blocking is safer) | Low |
| products | (not in 001) | public SELECT only | MERGE (add admin write policy) | Med |
| cart_items | cart_all_own | **RLS on, NO policies → deny-all** | REPO (add owner ALL policy) | Med |
| wishlists | (n/a) | **RLS on, NO policies → deny-all** | REPO (add owner ALL policy) | Med |
| categories | (n/a) | **RLS on, NO policies → deny-all** | REPO (add public SELECT + admin write) | Med |

## 11. Storage Buckets
| Item | Code expects | Live | Verified? |
|---|---|---|---|
| bucket `products` | used by `adminService.uploadImages` | **NOT verifiable from schema dump** (bucket rows are data) | ❌ Needs dashboard or `select id,public from storage.buckets` |

## 12. Storage Policies
| Item | Code expects | Live | Canonical | Risk |
|---|---|---|---|---|
| policies on `storage.objects` for `products` | implied (upload + public read) | **NONE user-defined** (RLS on `storage.objects` = default deny) | REPO add (admin write, public read) | Med |

---

## Frontend dependency & notes (per difference)

Maps each key difference to the frontend code that depends on it (the per-object tables
above carry repo/live/canonical/migration/data/risk; this table adds the **frontend
dependency** and **notes** dimensions the spec requires).

| Object / difference | Frontend dependency | Notes |
|---|---|---|
| table `cart` vs `cart_items` | `cartService` (5 calls), `CartContext` | Live table deny-all (no RLS policy) even once name fixed |
| table `wishlist` vs `wishlists` | `wishlistService`, `WishlistContext` realtime | Deny-all until owner policy added |
| RPC `place_order` absent | `orderService.placeOrder` → `Checkout.jsx` | Client fallback removed in Phase 1 → checkout hard-fails until created |
| `orders.total_amount` vs `total` | `orderService.mapOrder`, `adminService` | `mapOrder` already falls back to `total_price`; add `total` |
| `orders.payment_status/note/updated_at` | `adminService.getOrders/updateOrderStatus`, `mapOrder` | Selecting/updating absent columns errors |
| `profiles.full_name` absent | `AuthContext.updateProfile`, `userService`, signup metadata, `adminService` joins | Silent data loss / join failures today |
| `profiles.role` default `customer`, no CHECK | `AuthContext.isAdmin`, `AdminRoute`, `adminService.updateUserRole` | Adopt `customer`/`admin`; **C-1 live** (no WITH CHECK) |
| `products.stock` absent | `adminService` low-stock/inventory, `place_order` | `.lt('stock',5)` errors; inventory screens broken |
| `products.discountPrice`/images absent | `CartContext.getItemPrice/getItemImage`, cards | Price falls back to `price`; images break |
| `products` PK `(id,name)` | `productService.getProductById` (`.eq('id').maybeSingle()`) | Composite PK allows dup `id`; blocks clean FKs |
| `order_items.image_url/created_at` absent | `orderService.mapOrder` (receipt) | Receipt image blank |
| `cart_items`/`wishlists` no UNIQUE | `cartService.addToCart` upsert logic, `wishlistService` | Dedupe before adding UNIQUE |
| `categories` dual model | `productService.getCategories` (text) vs `adminService` (table) | Two sources of truth |
| tables `payments`/`pickup_locations`/`addresses` absent | `paymentService`, `adminService` pickup, `userService` addresses | Deferred: guard/disable or design in Phase 2 |
| storage `products` bucket/policies | `adminService.uploadImages` | Bucket existence **unverified**; `getPublicUrl` misused in code |

## Summary of drift
- **9 table-level issues** (2 name mismatches, 2 missing tables, 5 column-set gaps).
- **1 High-risk structural issue**: `products` composite PK `(id, name)`.
- **3 missing DB functions** (checkout depends on `place_order`).
- **3 tables with RLS-on/no-policy (deny-all):** `cart_items`, `wishlists`, `categories`.
- **1 Critical live security gap:** `profiles` UPDATE policy has no `WITH CHECK`.
- **Storage bucket/policy state unverified** (requires dashboard/data query).

No schema was modified. Proceed to `Canonical_Schema_Proposal.md`.
