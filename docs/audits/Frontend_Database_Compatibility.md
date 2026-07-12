# Frontend ↔ Database Compatibility Audit

**Date:** 2026-07-12
**Scope:** Every frontend module that talks to Supabase, checked against the **verified live schema**.
**Evidence:** live dump (`public`/`storage`) + source under `frontend/src/`.
**Note:** This is analysis only. No code or database was changed in this phase.

---

## Access-point inventory

| File | Tables / RPC / Storage used | Live-compatible? |
|---|---|---|
| `lib/supabaseClient.js` | `createClient(url, anon)` | ✅ (env-driven) |
| `lib/supabase.js` | re-exports `supabaseClient` | ✅ |
| `context/AuthContext.jsx` | `auth.*`, `profiles` (select/update), reads `profile.role` | 🟡 writes `full_name` (missing col) |
| `context/CartContext.jsx` | `auth.*`, via `cartService`; reads `product.discountPrice/images/image_url` | ❌ table + columns |
| `context/WishlistContext.jsx` | `wishlistService`, realtime channel on **`table: 'wishlist'`** | ❌ table name |
| `services/cartService.js` | **`.from('cart')`** (+ `products(*)`) | ❌ table `cart` absent (live `cart_items`) |
| `services/wishlistService.js` | **`.from('wishlist')`** (+ `products(*)`) | ❌ table `wishlist` absent (live `wishlists`) |
| `services/productService.js` | `products` (name/slug/category/price) | 🟡 works for read; assumes single PK |
| `services/orderService.js` | **`rpc('place_order')`**, `orders`(`total_amount`), `order_items`(`image_url`), `profiles`(`full_name`) | ❌ RPC + columns |
| `services/adminService.js` | `orders`(`total_amount`,`payment_status`,`note`,`updated_at`), `products`(`stock`), `categories`, **`pickup_locations`**, storage `products` | ❌ many |
| `services/userService.js` | `profiles` upsert (`full_name`), `addresses` | ❌ `full_name` + **`addresses`** table absent |
| `services/paymentService.js` | **`.from('payments')`** | ❌ table absent |

---

### Hooks & Components coverage

- **Hooks:** the only remaining hooks are `useDebounce` and `usePagination` — **neither
  touches Supabase** (pure client utilities). No DB compatibility impact. (The former
  DB-touching hooks were dead code removed in Phase 1.)
- **Components:** components do **not** call Supabase directly; they consume `contexts`
  (`useCart`, `useWishlist`, `useAuth`) and `services`. Therefore all DB incompatibilities
  are captured at the service/context layer below. Component-level breakage is a *symptom*
  of the service/context issues (e.g., `Cart.jsx`, `Wishlist.jsx`, `AdminInventory.jsx`,
  `AdminPickupLocations.jsx`, `Checkout.jsx`, `ProductDetail.jsx`, admin product form image
  upload) and resolves when the underlying service/DB items are fixed.

### Consolidated incompatibility list (file · issue · fix · priority)

| # | File | Issue | Recommended change | Priority |
|---|---|---|---|---|
| 1 | `services/cartService.js` | `.from('cart')` — table absent (live `cart_items`) | rename table refs; needs owner RLS | **Critical** |
| 2 | `services/wishlistService.js` + `context/WishlistContext.jsx` | `.from('wishlist')` / realtime `table:'wishlist'` — live `wishlists` | rename table + channel filter; needs owner RLS | **Critical** |
| 3 | `services/orderService.js` | `rpc('place_order')` absent on live | create function (DB); no code change if signature kept | **Critical** |
| 4 | `services/paymentService.js` | `.from('payments')` table absent | guard/disable or design table (deferred) | **Critical** |
| 5 | `services/userService.js` | `.from('addresses')` table absent | guard/disable or design table (deferred) | **Critical** |
| 6 | `services/adminService.js` (+ `AdminPickupLocations.jsx`) | `.from('pickup_locations')` absent | guard/disable or design table (deferred) | **Critical** |
| 7 | `context/AuthContext.jsx`, `services/userService.js`, `services/adminService.js` | `profiles.full_name` absent | add column (DB); code already sends it | High |
| 8 | `services/orderService.js`, `services/adminService.js` | `orders.total_amount` vs live `total` | read/write `total` per canonical | High |
| 9 | `services/adminService.js` | `orders.payment_status`/`note`/`updated_at` absent | add columns + trigger (DB) | High |
| 10 | `services/adminService.js` | `products.stock` absent | add column (DB) | High |
| 11 | `context/CartContext.jsx`, product cards | `products.discountPrice`/`images`/`image_url` absent | add columns; map snake_case in code | High |
| 12 | `services/productService.js` | `products` composite PK `(id,name)` | PK→`(id)` (DB, gated) | Medium |
| 13 | `services/adminService.js` | `getPublicUrl` destructured as `publicURL` (always undefined) | use `{ data: { publicUrl } }`; add storage policies | Medium |
| 14 | `services/cartService.js` | `this.removeFromCart`/`this.getCart` throw (arrow-fn `this`) | call `cartService.*` directly | Medium |
| 15 | `services/productService.js` + `services/adminService.js` | categories dual model (text vs `categories` table) | standardize on `categories`+`category_id` | Medium |
| 16 | `context/WishlistContext.jsx` | realtime bound to wrong table name | fix with #2 | Low |
| 17 | live `profiles.phone` default `'+254...'` | placeholder literal default | cosmetic; optional cleanup | Low |

## Incompatibilities and required code changes (detail)

### CRITICAL — features fully broken against live

1. **Cart table name** (`cartService.js`)
   - Now: `.from('cart')`. Live table is `cart_items`.
   - Fix: replace all `'cart'` → `'cart_items'` (5 calls). Also live has RLS deny-all →
     requires DB owner policy (see Migration Strategy) before it works.

2. **Wishlist table name** (`wishlistService.js` + `WishlistContext.jsx`)
   - Now: `.from('wishlist')` and realtime `table: 'wishlist'`. Live is `wishlists`.
   - Fix: `'wishlist'` → `'wishlists'` (3 calls + 1 realtime filter). Needs DB owner policy.

3. **Checkout RPC** (`orderService.placeOrder`)
   - Now: `supabase.rpc('place_order', { p_user_id })`. **Function absent on live.**
   - Fix (DB): create `place_order()` (Migration Strategy). No code change if signature kept.
   - Note: the client fallback was removed in Phase 1, so checkout is currently a hard fail
     until the function exists.

4. **`payments` table** (`paymentService.js`)
   - Now: `.from('payments')`. Table absent on live.
   - Fix: disable/guard `paymentService`, or create the table (feature decision — deferred).

5. **`addresses` table** (`userService.getAddresses/addAddress/...`)
   - Now: `.from('addresses')`. **Table absent on live** (not in dump).
   - Fix: disable/guard address features, or design the table (deferred). *Previously
     unflagged — surfaced by this audit.*

6. **`pickup_locations` table** (`adminService` + `AdminPickupLocations.jsx`)
   - Now: `.from('pickup_locations')`. Table absent on live.
   - Fix: disable/guard, or design the table (deferred).

### HIGH — columns missing on live (silent failures / wrong data)

7. **`profiles.full_name`** (`AuthContext.updateProfile`, `userService`, signup metadata,
   `adminService` selects `profiles(full_name)`)
   - Live `profiles` has no `full_name` → writes error or are dropped; admin joins fail.
   - Fix (DB): add `full_name`. Code already sends it.

8. **`orders.total_amount` vs live `total`** (`orderService.mapOrder`, `adminService.getStats/getOrders`)
   - Code reads `total_amount`/`total_price`; live column is `total`.
   - Fix (code, if canonical keeps `total`): read/write `total`. `mapOrder` already
     falls back to `total_price`; add `total`.

9. **`orders.payment_status` / `note` / `updated_at`** (`adminService.getOrders/updateOrderStatus`, `mapOrder`)
   - Absent on live → select errors / update writes to non-existent column.
   - Fix (DB): add columns (+ `updated_at` trigger).

10. **`products.stock`** (`adminService.getStats` low-stock, `getInventory`, `getLowStock`,
    `updateStock`, and `place_order` stock logic)
    - Absent on live → `.lt('stock', 5)` errors; inventory screens broken.
    - Fix (DB): add `stock`.

11. **`products.discountPrice` / `images` / `image_url`** (`CartContext.getItemPrice/getItemImage`,
    `orderService`, product cards)
    - Absent on live → pricing falls back to `price` (acceptable) but images break.
    - Fix (DB): add `discount_price` + image fields; map in code (snake_case).

### MEDIUM — structural / behavioral

12. **`products` composite PK `(id, name)`** — `.eq('id', ...).maybeSingle()` may return
    multiple rows if `name` differs for same `id` (shouldn’t happen, but PK allows it).
    Fix (DB, approval-gated): PK → `(id)`.

13. **Storage upload API misuse** (`adminService.uploadImages`)
    - `const { publicURL } = supabase.storage.from('products').getPublicUrl(path)` — wrong.
      Modern SDK returns `{ data: { publicUrl } }`. `publicURL` is always `undefined`.
    - Also bucket `products` existence + policies unverified.
    - Fix (code): `const { data: { publicUrl } } = ...`. Fix (DB): storage policies.

14. **`cartService` broken `this` references** (`updateQuantity` → `this.removeFromCart`,
    `getCartLegacy`/`addToCartLegacy` → `this.getCart`)
    - Methods are arrow functions on an object literal → `this` is not the service object;
      these calls throw `TypeError` at runtime.
    - Fix (code): call `cartService.removeFromCart(...)` / `cartService.getCart(...)` directly.

15. **Categories dual model** (`productService.getCategories` derives categories from
    `products.category` text; `adminService` CRUDs the `categories` table)
    - Two sources of truth. Fix (code + DB): standardize on `categories` + `category_id`.

### LOW

16. Realtime: `CartContext` has no realtime; `WishlistContext` subscribes to wrong table
    name (see #2). Cosmetic until wishlist works.
17. `profiles.phone` live default `'+254...'` is a placeholder literal — harmless but odd.

---

## Required code-change checklist (for the reconciliation PR — do NOT do in this phase)

- [ ] `cartService.js`: `'cart'`→`'cart_items'`; fix `this.*` calls.
- [ ] `wishlistService.js`: `'wishlist'`→`'wishlists'`.
- [ ] `WishlistContext.jsx`: realtime `table: 'wishlist'`→`'wishlists'`.
- [ ] `orderService.js` / `adminService.js`: `total_amount`→`total` (per canonical).
- [ ] `CartContext.jsx` / cards: map `discount_price`, image fields (snake_case).
- [ ] `adminService.uploadImages`: fix `getPublicUrl` destructuring.
- [ ] Guard/disable `paymentService`, `userService` address methods, and
      `AdminPickupLocations` until those tables are designed (or design them in Phase 2).
- [ ] `productService.getCategories` / category usage: move to `categories` + `category_id`.

## DB-side prerequisites (see Migration_Strategy.md)
- Add columns: `profiles.full_name/updated_at`, `orders.payment_status/note/updated_at`,
  `products.stock/discount_price/image_url/images`, `order_items.image_url/created_at`.
- Add RLS owner policies for `cart_items`, `wishlists`; public/admin for `categories`, `products` writes.
- Create `place_order()`, `is_admin()`, `handle_new_user()`.
- Storage policies for `products` bucket (+ verify the bucket exists).
