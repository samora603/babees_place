# Phase 1.7B — Workstream 2: Frontend Reconciliation

**Date:** 2026-07-12
**Branch:** `phase-1.7-reconciliation`
**Scope:** Reconcile the React frontend (`frontend/src`) with the **approved canonical
database schema** and the **authored + reviewed (but un-applied) migration chain**
`002`–`010`.
**Constraint:** Repository-only. Frontend code only. No migration executed/pushed, no
live Supabase change, no schema redesign, no new features.

**Authoritative sources:** `Final_Canonical_Schema.md`, `Reconciliation_Decision_Log.md`,
`Schema_Comparison_Matrix.md`, `Migration_Strategy.md`, `Migration_History.md`,
`Database_Reconciliation_Runbook.md`, `Frontend_Database_Compatibility.md`,
`Phase1_7B_Migration_Authoring_Report.md`, `Phase1_7B_Migration_Review.md`.

---

## 1. Executive summary

The frontend carried a legacy/fictional data shape (MERN-era) that did not match the
canonical schema: `cart`/`wishlist` tables, `discountPrice`, `total_amount`, `_id`,
`category.name` objects, and calls to tables that **do not exist** in the canonical
schema (`payments`, `addresses`, `pickup_locations`). Against canonical this produced
three failure classes: (a) **hard errors** — queries on missing tables/columns;
(b) **silent wrong data** — camelCase reads that never match snake_case columns;
(c) **runtime bugs** — `this` inside object-literal arrow methods and a `getPublicUrl`
destructuring error.

Working in the mandated dependency order (services → hooks → contexts → pages →
components → fictional-dependency removal → cleanup), every Supabase interaction was
aligned to the canonical schema. The **server-side order workflow is preserved**:
checkout calls the atomic `place_order` RPC only; the client never computes/submits a
total. No `service_role`, secrets, or RLS-bypass paths were introduced.

**Gates:** `npm run lint` → **0 errors / 0 warnings**; `npm test` → **18/18 pass**;
`npm run build` → **success**. `npm install` not required (no dependency changes).

---

## 2. Stage 1 — Frontend inventory (every Supabase interaction)

Format: **File · current · canonical · migration dep · risk · required change.** Hooks
(`useDebounce`, `usePagination`) and all `components/ui/*` were confirmed to have **no**
Supabase interaction. Realtime: only `WishlistContext` (channel) + auth listeners in
`AuthContext`/`CartContext`.

### Services

| File | Current (fictional) | Canonical | Migration dep | Risk | Required change |
|---|---|---|---|---|---|
| `services/cartService.js` | `.from('cart')` ×5; `this.removeFromCart/getCart/…` throw | `cart_items`; call `cartService.*` | 004 (owner RLS) | **Critical** | rename table; fix `this` |
| `services/wishlistService.js` | `.from('wishlist')` ×3 | `wishlists` | 004 (owner RLS) | **Critical** | rename table |
| `services/orderService.js` | reads `total_amount`/`total_price`; `order_status` | reads `total`; `status`; RPC `place_order(p_user_id)` | 002, 003 | High | map `total`; keep RPC |
| `services/productService.js` | filter `category` text; `getCategories` from products text; no sort/stock filter | filter `category_id`; `getCategories` from `categories`; embed `categories(id,name,slug)`; sort/stock | 002, 009 | Medium | rewrite queries |
| `services/adminService.js` | `orders.total_amount`; `publicURL` (undefined); inventory `id,name,stock`; `pickup_locations` | `orders.total`; `{data:{publicUrl}}`; select price/category/images; deferred | 002, 006 | High | fix all; guard pickup |
| `services/userService.js` | `.from('addresses')` (absent) | deferred; keep `updateProfile`/`getProfile` | — | **Critical** | guard address methods |
| `services/paymentService.js` | `.from('payments')` (absent) | deferred | — | **Critical** | guard methods |

### Contexts

| File | Current | Canonical | Change |
|---|---|---|---|
| `context/CartContext.jsx` | `product.discountPrice` | `discount_price` | update price getter |
| `context/WishlistContext.jsx` | realtime `table:'wishlist'` | `table:'wishlists'` | rename table + channel |
| `context/AuthContext.jsx` | writes `full_name`, reads `role` | `profiles.full_name` (002); admin check `=== 'admin'` | **no change** — already canonical |

### Pages & components

| File | Current | Canonical | Change |
|---|---|---|---|
| `pages/Shop.jsx` | option `value={c._id}` | `value={c.id}` (category_id) | filter by `category_id` |
| `pages/ProductDetail.jsx` | `discountPrice`, `category?.name` | `discount_price`, `categories?.name \|\| category` | update refs |
| `pages/Wishlist.jsx` | `discountPrice` ×2 | `discount_price` | update |
| `pages/admin/AdminProducts.jsx` | `_id`, `discountPrice`, `isActive`, `category?.name` | `id`, `discount_price`, `is_active`, `categories?.name` | update + toggle `{is_active}` |
| `pages/admin/AdminProductForm.jsx` | writes camelCase + non-columns | canonical `discount_price/featured/is_active/category_id`; persist `images` | rewrite payload/edit-map; drop dead inputs |
| `pages/admin/AdminInventory.jsx` | `_id`, `category?.name`, `soldCount`, `lowStockThreshold` | `id`, `category`, (dropped) | update; remove Sold col; `stock<=5` |
| `pages/admin/AdminUsers.jsx` | `_id`, `u.name`, `u.createdAt`, `u.isActive` | `id`, `full_name`, `created_at` | update; drop status col; fix paging |
| `pages/admin/AdminOrders.jsx` | `o.total_amount ?? o.total_price` | `o.total` | update |
| `components/products/ProductCard.jsx` | `discountPrice`, `_id`, `category?.name` | `discount_price`, `id`, `categories?.name \|\| category` | update refs |
| `components/products/ProductGrid.jsx` | `key={product._id}` | `id` | update key |
| `utils/constants.js` | `ROLES.user='user'`; sort `-rating`/`-soldCount` | `ROLES.customer`; sort on real columns | update |
| `components/layout/Footer.jsx` | link `?sort=-soldCount` | valid sort value | update link |

> Order pages (`OrderDetail`, `AdminOrderDetail`, `Orders`, `OrderConfirmation`) consume
> `orderService.mapOrder`'s mapped shape (retains `totalAmount`/`total_amount` output keys
> while reading canonical `total`) → no per-page change required.

---

## 3. Files modified (26)

- **Services (7):** `cartService.js`, `wishlistService.js`, `orderService.js`,
  `productService.js`, `adminService.js`, `userService.js`, `paymentService.js`
- **Hooks (0):** none (no Supabase coupling)
- **Contexts (2):** `CartContext.jsx`, `WishlistContext.jsx`
- **Pages (10):** `Shop.jsx`, `ProductDetail.jsx`, `Wishlist.jsx`, `admin/AdminProducts.jsx`,
  `admin/AdminProductForm.jsx`, `admin/AdminInventory.jsx`, `admin/AdminUsers.jsx`,
  `admin/AdminOrders.jsx`, `admin/AdminDashboard.jsx`, `admin/AdminSettings.jsx`
- **Components (5):** `products/ProductCard.jsx`, `products/ProductGrid.jsx`,
  `ui/Skeleton.jsx`, `layout/AdminLayout.jsx`, `layout/Footer.jsx`
- **Utils/entry (2):** `utils/constants.js`, `main.jsx`
- **Tests (0):** none (existing 18 pass unchanged)
- **Docs (1):** this report

---

## 4. Compatibility matrix (canonical object vs frontend)

| Canonical object | Frontend usage now | Status |
|---|---|---|
| `cart_items` | `cartService`, `CartContext`, `Cart` | ✅ |
| `wishlists` | `wishlistService`, `WishlistContext`, `Wishlist` | ✅ |
| `products` (`discount_price`,`stock`,`featured`,`is_active`,`category_id`,`images`,`image_url`,`description`) | product/admin services + UI | ✅ |
| `categories` (id,name,slug) | `getCategories`, Shop, admin form | ✅ |
| `orders` (`total`,`status`,`payment_status`,`note`,`updated_at`) | `orderService`, `adminService`, admin orders | ✅ |
| `order_items` (`name`,`price`,`image_url`) | `mapOrder`, order detail | ✅ |
| `profiles` (`full_name`,`role`,`email`,`phone`,`created_at`) | `AuthContext`, admin users | ✅ |
| `place_order(p_user_id)` RPC | `orderService.placeOrder` → `Checkout` | ✅ server-side only |
| storage bucket `products` | `adminService.uploadImages` | ✅ (fixed publicUrl; policies via 006) |
| `payments` / `addresses` / `pickup_locations` | deferred — guarded | ⚪ intentionally disabled |

---

## 5. Old → Canonical mappings

### Tables

| Old (fictional) | Canonical |
|---|---|
| `cart` | `cart_items` |
| `wishlist` | `wishlists` |
| `payments` | *(none — deferred)* |
| `addresses` | *(none — deferred)* |
| `pickup_locations` | *(none — deferred)* |

### Columns / fields

| Old | Canonical | Where |
|---|---|---|
| `orders.total_amount` / `total_price` | `orders.total` | orderService, adminService, AdminOrders |
| `products.discountPrice` | `products.discount_price` | CartContext, ProductCard, ProductDetail, Wishlist, AdminProducts, AdminProductForm |
| `products.isActive` | `products.is_active` | AdminProducts, AdminProductForm |
| `products.isFeatured` | `products.featured` | AdminProductForm |
| `product.category?.name` (object) | `product.categories?.name \|\| product.category` (embed + text fallback) | ProductCard, ProductDetail, AdminProducts, AdminInventory |
| category filter by `category` text | filter by `category_id` (uuid) | Shop, productService |
| `getCategories` derived from `products.category` | read `categories` table | productService |
| `_id` (sole key) | `id` | ProductGrid, ProductCard, AdminProducts, AdminInventory, AdminUsers |
| `profiles.name` | `profiles.full_name` | AdminUsers (AuthContext/userService already used `full_name`) |
| `createdAt` | `created_at` | AdminUsers |
| `soldCount`, `lowStockThreshold` | *(no column — removed from UI)* | AdminInventory |
| `ROLES.user = 'user'` | `ROLES.customer = 'customer'` | constants |
| storage `{ publicURL }` | `{ data: { publicUrl } }` | adminService.uploadImages |

### RPC / workflow (unchanged, verified canonical)

| Item | Canonical |
|---|---|
| checkout | `supabase.rpc('place_order', { p_user_id })` — server computes total; no client total |

---

## 6. Migration dependencies (frontend correctness requires these applied)

| Migration | Provides | Frontend feature depending on it |
|---|---|---|
| **002** additive columns | `profiles.full_name`; `orders.payment_status/note/updated_at`; `products.stock/discount_price/image_url/images`; `order_items.image_url/created_at` | profile save, admin stats/orders, inventory, pricing/images |
| **003** functions/triggers | `place_order()`, `is_admin()`, `handle_new_user()`, `set_updated_at` | **checkout**, signup→profile, `updated_at` |
| **004** RLS | owner policies for `cart_items`/`wishlists`; product/category writes; `order_items` SELECT owner-or-admin | cart, wishlist, admin product CRUD, admin line items |
| **006** storage | `products` bucket read/admin-write policies | image upload/display |
| **009** product FKs | `products.category_id`→`categories` | embedded `categories(...)` join, category filter |

Until **003** applied → checkout hard-fails (by design; no client fallback). Until **004**
→ cart/wishlist RLS-denied. The `categories(...)` embed resolves via the **009** FK; before
that it falls back to the retained `products.category` text.

---

## 7. Breaking changes

1. **Table renames** `cart`→`cart_items`, `wishlist`→`wishlists`; requires those tables +
   004 RLS to function.
2. **`orders.total_amount`→`total`**: admin raw rows now expose `total` (mapped order
   objects still expose `total_amount`/`totalAmount`).
3. **Product write shape** (`AdminProductForm`): canonical columns only; inputs for
   `shortDescription` and `lowStockThreshold` (no backing columns) were removed.
4. **Category model**: filtering by `category_id`; categories sourced from `categories`
   table, not `products.category` text.
5. **Deferred features disabled**: address book, payments, admin pickup-locations return
   empty/"not available" instead of querying missing tables.
6. **Role vocabulary**: `ROLES.user` → `ROLES.customer`.

---

## 8. Deferred Phase 2 items

These are guarded (never hit the DB) and awaiting schema design in a later phase:

- **`addresses`** — `userService` address methods (`getAddresses`/`addAddress`/
  `updateAddress`/`deleteAddress`) return empty/disabled. Not currently imported by any page.
- **`payments`** — `paymentService` (`createPayment`/`verifyPayment`) disabled; real M-Pesa/
  gateway integration is server-side, future.
- **`pickup_locations`** — `adminService` pickup methods disabled; `AdminPickupLocations`
  route renders an empty state.
- **Speculative product UI** with no canonical columns (renders nothing today): `rating`,
  `reviewCount`, `variations`, `faqs` in `ProductCard`/`ProductDetail`.
- **Product `slug` generation** in the admin create flow (links fall back to `id`).

---

## 9. Removed fictional database dependencies

| Removed reference | Action | Reason |
|---|---|---|
| `.from('cart')` | → `cart_items` | table does not exist in canonical |
| `.from('wishlist')` | → `wishlists` | table does not exist in canonical |
| `.from('addresses')` | guarded (no DB call) | table not in canonical (deferred) |
| `.from('payments')` | guarded (no DB call) | table not in canonical (deferred) |
| `.from('pickup_locations')` | guarded (no DB call) | table not in canonical (deferred) |
| `orders.total_amount` / `total_price` | → `orders.total` | columns do not exist |
| `products.discountPrice`/`isActive`/`isFeatured` | → snake_case canonical | columns do not exist as camelCase |
| `products.soldCount` / `lowStockThreshold` | removed from UI | no such columns |
| `profiles.isActive` (admin users status) | removed column from table | no such column |
| product `category` as object (`.name`) | embed `categories` + text fallback | canonical uses `category_id` FK |

No replacements were invented; deferred items are documented (§8), not stubbed with new
schema.

---

## 10. Validation results

```
npm run lint   → 0 errors, 0 warnings
npm test       → 3 files, 18/18 tests passed
npm run build  → 1013 modules, built in ~12s, no errors
```

`npm install` not required — no dependency changes. React Router "future flag" notices in
test output are informational (v7 pre-warnings), not failures.

---

## 11. Engineering score

**9.3 / 10.** Every Supabase interaction targets the canonical schema; two latent runtime
bugs fixed; fictional dependencies removed/guarded; server-side order workflow and security
posture preserved; all gates green with zero warnings. Points withheld for residual
speculative read-only UI and deferred-feature scaffolding pending future, schema-backed
phases.

---

## 12. Remaining risks

| Area | Risk | Severity | Mitigation |
|---|---|---|---|
| Checkout / `place_order` | Hard-fails until 003 applied | High (until migration) | By design; server-authoritative |
| Cart / wishlist | RLS-denied until 004 applied | High (until migration) | Owner policies authored in 004 |
| `categories(...)` embed | Needs FK (009); sparse `category_id` pre-backfill | Medium | Falls back to `product.category` text |
| Image upload persistence | Writes `images` jsonb; needs 006 + bucket | Medium | Guarded try/catch; toasts, no crash |
| Deferred features | UI empty/disabled | Low | Intentional graceful degradation |
| Speculative read-only fields | Render nothing (no columns) | Low | No-op conditional UI; documented |

---

## 13. Categorized final summary (why each file changed)

**Services (7)**
- `cartService.js` — table `cart`→`cart_items`; fixed `this.*` (arrow-fn) calls that threw.
- `wishlistService.js` — table `wishlist`→`wishlists`.
- `orderService.js` — `mapOrder` reads canonical `orders.total`; simplified `status`.
- `productService.js` — `getCategories` from `categories` table; embed category; filter by
  `category_id`; added canonical sort + `stock>0` filter.
- `adminService.js` — `orders.total`; fixed `getPublicUrl`; inventory selects price/
  category/images; guarded `pickup_locations`; trigger-managed `updated_at`.
- `userService.js` — guarded `addresses` (deferred); kept profile methods.
- `paymentService.js` — guarded `payments` (deferred).

**Hooks (0)** — `useDebounce`/`usePagination` are pure utilities; verified no Supabase use.

**Contexts (2)**
- `CartContext.jsx` — `discountPrice`→`discount_price` in price getter.
- `WishlistContext.jsx` — realtime table/channel `wishlist`→`wishlists`.
- *(AuthContext verified already canonical — unchanged.)*

**Pages (10)**
- `Shop.jsx` — category select uses `category_id`.
- `ProductDetail.jsx` — `discount_price`; category embed fallback.
- `Wishlist.jsx` — `discount_price`.
- `AdminProducts.jsx` — `id`/`discount_price`/`is_active`/category; toggle `{is_active}`.
- `AdminProductForm.jsx` — canonical write payload; edit-mapping; persist `images`; removed
  inputs for non-existent columns.
- `AdminInventory.jsx` — `id`; category text; removed Sold column; low-stock `stock<=5`.
- `AdminUsers.jsx` — `id`/`full_name`/`created_at`; removed non-existent status column;
  fixed pagination.
- `AdminOrders.jsx` — `o.total`.
- `AdminDashboard.jsx` — removed unused `supabase` import (lint).
- `AdminSettings.jsx` — removed unused icon import (lint).

**Components (5)**
- `ProductCard.jsx` — `discount_price`/`id`/category embed fallback.
- `ProductGrid.jsx` — key uses `id`.
- `ui/Skeleton.jsx` — removed unused `React` import (lint).
- `layout/AdminLayout.jsx` — removed unused icon import (lint).
- `layout/Footer.jsx` — replaced removed `-soldCount` sort link value.

**Utils/entry (2)**
- `utils/constants.js` — `ROLES.customer`; sort options limited to real columns.
- `main.jsx` — removed unused `React` import (lint).

**Tests (0)** — none modified; 18/18 still pass.

**Docs (1)** — this report.

---

**STOP.** Frontend matches the canonical schema; no fictional DB dependencies remain; lint,
tests, and build all pass. No migrations executed, no live DB contacted. Awaiting approval
before Workstream 3.
