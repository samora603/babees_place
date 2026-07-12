# Phase 2 — Workstream 1: Inventory Management — Design Document

**Status:** Design only — no implementation  
**Date:** 2026-07-12  
**Branch:** `phase-1.7-reconciliation`  
**Prerequisite:** Phase 1.8 complete (migrations `001`–`010` applied on live)

---

## 1. Objective

Implement a **complete inventory management system** that:

- Gives admins reliable tools to view, filter, and update stock levels
- Prevents overselling through layered client + server validation
- Surfaces low-stock and out-of-stock conditions clearly
- Integrates with existing checkout (`place_order` RPC) without breaking current flows
- Aligns with the canonical schema and deferred Phase 2 decisions (D-RPC-4, D-PROD-11)

**Non-goals for this workstream:**

- Inventory reservations / cart holds (D-FEAT-5 — deferred)
- Variant/SKU-level stock (ProductDetail variations UI is cosmetic today)
- Full audit logging subsystem (D-FEAT-6 — deferred; optional lightweight stock-change log)
- Coupons, shipping, payments (separate workstreams)

---

## 2. Current State (Audit)

### 2.1 Database / Supabase

| Item | Status | Notes |
|---|---|---|
| `products.stock` | ✅ Exists | `integer NOT NULL DEFAULT 0` — added in migration `002`, live |
| `products.is_active` | ✅ Exists | `boolean NOT NULL DEFAULT true` — added in `002`; admin toggle works |
| `place_order()` stock lock | ✅ Exists | `FOR UPDATE`, validates `stock >= quantity`, decrements atomically (`003`) |
| `CHECK (stock >= 0)` | ❌ Missing | Negative stock theoretically possible under race conditions |
| `idx_products_is_active` | ✅ Exists | Migration `010` |
| Stock index | ❌ Missing | Not required at MVP scale; low-stock queries use `.lt('stock', N)` |
| `cancel_order()` + stock restore | ❌ Missing | Documented as Phase 2 (D-RPC-4) |
| `is_active` in `place_order` | ❌ Missing | Inactive products can still checkout if in cart |
| `is_active` in storefront RLS/SELECT | ❌ Missing | Public read returns inactive products |
| Inventory audit table | ❌ Missing | Stock edits are silent `UPDATE`s |
| Cart UNIQUE constraint | ✅ Exists | `009` — prevents duplicate lines affecting stock decrement |

**Authoritative stock decrement path:** only `place_order()` — no frontend or direct client UPDATE on checkout.

### 2.2 Backend (Supabase-only)

There is no separate backend server. Inventory backend = migrations + RPC + RLS.

| Component | Inventory role |
|---|---|
| `003_functions_and_triggers.sql` | `place_order()` — stock validation + decrement |
| `004_rls_and_security.sql` | `products_write_admin` — admin-only product writes |
| `002_additive_columns.sql` | `stock`, `is_active` columns |
| `010_performance_optimizations.sql` | `idx_products_is_active` |

### 2.3 Frontend — What Exists

#### Services

| File | Inventory capability | Gap |
|---|---|---|
| `adminService.js` | `getInventory`, `getLowStock`, `updateStock`, `getStats` (lowStockCount) | `getInventory` **ignores** `stockStatus`/`limit` params; `getLowStock` unused |
| `productService.js` | `inStock` filter → `stock > 0` | No `is_active` filter on storefront |
| `cartService.js` | Cart CRUD | **No stock checks** |
| `orderService.js` | `placeOrder` → RPC | Server-side only; no pre-flight client validation |

#### Admin UI

| Page | Capability | Gap |
|---|---|---|
| `AdminInventory.jsx` | Table, inline stock edit, filter buttons | **Filters non-functional**; no search/sort/bulk; category display inconsistent |
| `AdminProducts.jsx` | Read-only stock column, `is_active` toggle | Stock edit only via Inventory or ProductForm |
| `AdminProductForm.jsx` | Required `stock` field on create/edit | Works correctly |
| `AdminDashboard.jsx` | Low-stock alert banner (`lowStockCount > 0`) | Links to Inventory; threshold hardcoded in service |

#### Storefront UI

| Page/Component | Capability | Gap |
|---|---|---|
| `Shop.jsx` | "In Stock Only" checkbox | Does not filter `is_active` |
| `ProductCard.jsx` | Out-of-stock badge, block add when `stock === 0` | Strict `=== 0` (null-unsafe); no low-stock indicator |
| `ProductDetail.jsx` | Stock display, quantity selector max, OOS disable | **Quantity selector ignored** — always adds 1 |
| `Cart.jsx` | Quantity +/- | **No stock ceiling** on increment |
| `Checkout.jsx` | RPC checkout, error toast on insufficient stock | No pre-checkout stock summary |

#### Constants / Hooks / Tests

| Area | Status |
|---|---|
| Shared `LOW_STOCK_THRESHOLD` | ❌ Magic number `5` scattered (`< 5` vs `<= 5` inconsistency) |
| Inventory hook | ❌ None |
| Inventory tests | ❌ None |

### 2.4 Known Bugs (must fix in implementation)

1. **AdminInventory filters broken** — UI passes `stockStatus` but `getInventory()` ignores it
2. **ProductDetail quantity bug** — `handleAddToCart` hardcodes `quantity: 1` instead of using selector state
3. **Cart overselling** — increment/add with no `product.stock` check
4. **Low-stock threshold inconsistent** — count uses `stock < 5`; UI highlight uses `stock <= 5`
5. **`getInventory` missing joins** — selects `category` text, not `categories(name)`; UI tries both

### 2.5 What Works Today (preserve)

- Server-authoritative checkout via `place_order` (stock lock + decrement)
- Admin inline stock update via `updateStock`
- Admin product form stock field
- Dashboard low-stock count (with threshold bug)
- Shop "In Stock Only" filter
- ProductCard/ProductDetail out-of-stock disable (for `stock === 0`)
- Admin `is_active` toggle on AdminProducts

---

## 3. Proposed Architecture

### 3.1 Design Principles

1. **Server remains authoritative** — `place_order` is the final gate; client validation is UX, not security
2. **Minimal schema changes** — leverage existing `stock` and `is_active`; avoid new tables unless audit log is in scope
3. **Single threshold constant** — one source of truth for "low stock" across admin UI and alerts
4. **Layered validation** — product detail → cart → checkout preview → RPC
5. **No breaking changes** — existing admin/product/checkout flows continue to work; gaps are filled, not replaced

### 3.1 Inventory Model

```
products
├── stock          integer NOT NULL DEFAULT 0   ← single source of truth
├── is_active      boolean NOT NULL DEFAULT true ← soft-hide (admin + optional storefront filter)
└── (no variants/reservations in WS1)

Stock lifecycle:
  Admin sets stock ──► Customer adds to cart (client-capped) ──► place_order validates + decrements
  Admin cancels order (future cancel_order RPC) ──► stock restored
```

### 3.2 Low-Stock Threshold

Introduce a shared frontend constant (no DB column needed at MVP):

```javascript
// frontend/src/constants/inventory.js
export const LOW_STOCK_THRESHOLD = 5;
// Low stock: 1 <= stock < LOW_STOCK_THRESHOLD
// Out of stock: stock <= 0
// In stock: stock > 0
```

Optional Phase 2.1 enhancement: admin-configurable threshold in a `settings` table — **out of scope for WS1**.

### 3.3 Validation Layers

| Layer | When | Action |
|---|---|---|
| L1 — ProductCard | Add to cart click | Block if `stock <= 0` |
| L2 — ProductDetail | Add to cart | Pass selected quantity; cap at `stock` |
| L3 — CartContext / cartService | Add/increment | Cap quantity at `product.stock`; toast if exceeded |
| L4 — Cart UI | Display | Show "Only N left" / disable `+` at max |
| L5 — Checkout | Pre-submit | Re-fetch cart with fresh stock; warn on insufficient items |
| L6 — place_order RPC | Order creation | Lock rows, validate, decrement (existing) |

### 3.4 Out-of-Stock Handling

| Surface | Behavior |
|---|---|
| Shop listing | "In Stock Only" filter (existing); optionally hide `is_active = false` |
| ProductCard | "Out of Stock" overlay; disable add-to-cart |
| ProductDetail | Disabled button; show `0 in stock` |
| Cart | Show warning badge on OOS lines; suggest remove or reduce |
| Checkout | Block submit if any line exceeds stock; link back to cart |

### 3.5 Low-Stock Alerts

| Surface | Behavior |
|---|---|
| AdminDashboard | Banner when any product has `0 < stock < LOW_STOCK_THRESHOLD` (fix threshold consistency) |
| AdminInventory | "Low Stock" filter shows matching products; orange highlight |
| AdminProducts | Orange stock column (existing, align threshold) |
| Storefront | Optional "Only X left" badge when `0 < stock <= LOW_STOCK_THRESHOLD` — **recommended, low effort** |

---

## 4. Database Changes

### 4.1 Recommended — New Migration `011_inventory_hardening.sql`

Minimal, non-breaking additions:

```sql
-- 1. Prevent negative stock at DB level
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_stock_nonneg_check;
ALTER TABLE public.products ADD CONSTRAINT products_stock_nonneg_check
  CHECK (stock >= 0) NOT VALID;
ALTER TABLE public.products VALIDATE CONSTRAINT products_stock_nonneg_check;

-- 2. Harden place_order: reject inactive products
-- (CREATE OR REPLACE in same migration — add is_active check in validation loop)

-- 3. cancel_order RPC (D-RPC-4) — restore stock on cancel
-- CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid) ...
```

| Change | Risk | Breaking? |
|---|---|---|
| `CHECK (stock >= 0)` | Low — validate after confirming no negative rows | No |
| `place_order` + `is_active` check | Low — rejects checkout of deactivated products | Behavior change (intended) |
| `cancel_order()` RPC | Medium — new admin/order cancel path | No (additive) |

### 4.2 Optional (defer if scope tight)

| Change | Notes |
|---|---|
| `idx_products_stock` | Only if low-stock queries become slow; not needed at current scale |
| `inventory_adjustments` audit table | `(id, product_id, old_stock, new_stock, changed_by, reason, created_at)` — nice-to-have |
| Storefront RLS filter `is_active OR is_admin()` | Canonical §7 optional; can be app-filter instead for WS1 |
| Configurable threshold in DB | Over-engineering for MVP |

### 4.3 No Changes Needed

- `stock` column — already exists
- `is_active` column — already exists
- Cart/wishlist UNIQUE — already exists (`009`)
- Storage / RLS for admin writes — already sufficient

---

## 5. Supabase Policy Changes

### 5.1 Current (sufficient for WS1)

- `products`: public SELECT (`Allow public read access`) + admin ALL (`products_write_admin`)
- Admin stock updates go through authenticated admin session + RLS — **no policy change required**

### 5.2 Optional Enhancement

Add storefront visibility filter at RLS level (canonical §7):

```sql
-- Replace blanket public SELECT with:
-- FOR SELECT USING (is_active = true OR public.is_admin())
```

**Recommendation:** Implement as **application filter** in WS1 (`productService` adds `.eq('is_active', true)` for non-admin queries). RLS change can follow in a gated migration if hiding inactive products at DB layer is required.

### 5.3 RPC Permissions

| Function | Change |
|---|---|
| `place_order` | Update body only (is_active check) — permissions unchanged |
| `cancel_order` | New — `REVOKE` from PUBLIC/anon; `GRANT` to authenticated (same pattern as `place_order`) |

---

## 6. API / Service Changes

### 6.1 New File: `frontend/src/constants/inventory.js`

- `LOW_STOCK_THRESHOLD = 5`
- Helper functions: `isOutOfStock(stock)`, `isLowStock(stock)`, `isInStock(stock)`

### 6.2 `adminService.js`

| Method | Change |
|---|---|
| `getInventory({ stockStatus, limit, search })` | Accept and apply filters: `low` → `stock > 0 AND stock < THRESHOLD`; `out` → `stock <= 0`; `in` → `stock >= THRESHOLD`; add `categories(name)` join; optional search on `name` |
| `getLowStock()` | Use shared threshold constant; wire to AdminInventory or remove if redundant |
| `getStats()` | Align `lowStockCount` query with `isLowStock` helper (`> 0 AND < THRESHOLD`) |
| `updateStock(id, { stock })` | Add client validation `stock >= 0`; optional `reason` param for future audit |
| `bulkUpdateStock([{ id, stock }])` | **New** — batch update for admin bulk edit (optional WS1 stretch) |

### 6.3 `productService.js`

| Method | Change |
|---|---|
| `getProducts()` | Add `.eq('is_active', true)` for storefront queries (non-admin) |
| `getProduct()` | Return stock; no change to shape |

### 6.4 `cartService.js` / `CartContext.jsx`

| Method | Change |
|---|---|
| `addToCart(userId, productId, quantity)` | Fetch/cache product stock; cap quantity; return structured error if exceeded |
| `updateQuantity(cartId, quantity)` | Same stock cap logic |
| `validateCartStock(userId)` | **New** — re-fetch all cart lines with fresh `products.stock`; return `{ valid, issues[] }` |

### 6.5 `orderService.js`

| Method | Change |
|---|---|
| `placeOrder()` | No RPC signature change; improve error mapping for `Insufficient stock for …` |
| `validateBeforeCheckout(userId)` | **New** — calls `cartService.validateCartStock` before RPC |

---

## 7. UI Changes

### 7.1 Admin Inventory (`AdminInventory.jsx`) — Primary WS1 deliverable

| Feature | Detail |
|---|---|
| Fix filters | Wire `stockStatus` to updated `getInventory` |
| Search | Text input filtering by product name |
| Sort | By name, stock (asc/desc), category |
| Columns | Add `is_active` badge; fix category via join |
| Inline edit | Keep existing; add validation feedback |
| Bulk edit | Optional: select multiple → set stock (stretch) |
| Empty states | Distinct messages per filter |
| Link | "Edit product" link to `/admin/products/:id/edit` |

### 7.2 Admin Dashboard (`AdminDashboard.jsx`)

- Use shared threshold constant
- Low-stock banner links to `/admin/inventory?filter=low` (query param)

### 7.3 Admin Products (`AdminProducts.jsx`)

- Align orange highlight with shared `isLowStock()` helper

### 7.4 Product Detail (`ProductDetail.jsx`)

- **Fix:** pass `quantity` state to `addToCart(product, quantity)`
- Show low-stock badge when applicable

### 7.5 Cart (`Cart.jsx`)

- Display per-line stock availability (`"Only 3 left"`)
- Disable `+` button when `quantity >= product.stock`
- Warning banner for lines where `quantity > stock` (stale cart)

### 7.6 Checkout (`Checkout.jsx`)

- Pre-submit: call `validateBeforeCheckout`
- If invalid: show itemized errors + "Return to Cart" CTA
- Do not call RPC until client validation passes

### 7.7 ProductCard / Shop

- Use shared helpers for OOS/low-stock badges
- Null-safe stock checks (`(stock ?? 0) <= 0`)

### 7.8 New Component (optional)

- `StockBadge.jsx` — reusable OOS / low-stock / in-stock indicator for admin + storefront

---

## 8. Files to Modify

### 8.1 Database (new migration only — do not edit historical)

| File | Action |
|---|---|
| `supabase/migrations/011_inventory_hardening.sql` | **Create** — CHECK constraint, `place_order` is_active guard, `cancel_order` RPC |

### 8.2 Frontend — Services

| File | Action |
|---|---|
| `frontend/src/constants/inventory.js` | **Create** |
| `frontend/src/services/adminService.js` | Modify — fix `getInventory`, align threshold |
| `frontend/src/services/productService.js` | Modify — `is_active` filter |
| `frontend/src/services/cartService.js` | Modify — stock cap validation |
| `frontend/src/services/orderService.js` | Modify — pre-checkout validation helper |

### 8.3 Frontend — Context / Pages / Components

| File | Action |
|---|---|
| `frontend/src/context/CartContext.jsx` | Modify — stock-aware add/setQuantity |
| `frontend/src/pages/admin/AdminInventory.jsx` | Modify — fix filters, search, sort |
| `frontend/src/pages/admin/AdminDashboard.jsx` | Modify — shared threshold |
| `frontend/src/pages/admin/AdminProducts.jsx` | Modify — shared threshold helper |
| `frontend/src/pages/ProductDetail.jsx` | Modify — quantity bug fix |
| `frontend/src/pages/Cart.jsx` | Modify — stock display + increment cap |
| `frontend/src/pages/Checkout.jsx` | Modify — pre-submit validation |
| `frontend/src/components/products/ProductCard.jsx` | Modify — null-safe + low-stock badge |
| `frontend/src/components/ui/StockBadge.jsx` | **Create** (optional) |

### 8.4 Tests

| File | Action |
|---|---|
| `frontend/src/constants/inventory.test.js` | **Create** — threshold helpers |
| `frontend/src/services/cartService.test.js` | **Create** — stock cap logic (mock Supabase) |
| `frontend/src/pages/admin/AdminInventory.test.jsx` | **Create** — filter behavior (optional) |

### 8.5 Documentation

| File | Action |
|---|---|
| `docs/technical/07_Admin.md` | Update — inventory section |
| `docs/database/Migration_History.md` | Update when `011` authored |

### 8.6 Files NOT Modified

- Historical migrations `001`–`010`
- `AdminProductForm.jsx` (stock field already works)
- Storage policies
- Auth / routing

---

## 9. Testing Strategy

### 9.1 Unit Tests

| Area | Cases |
|---|---|
| `inventory.js` helpers | `isOutOfStock(0)`, `isLowStock(3)`, `isInStock(10)`, edge null/undefined |
| Cart stock cap | Add when stock=5, increment to 6 → capped at 5; OOS product rejected |
| Admin filter logic | `stockStatus=low` returns only `1..THRESHOLD-1` |

### 9.2 Integration / Smoke (manual or E2E)

| Scenario | Expected |
|---|---|
| Admin updates stock inline | Reflects in AdminInventory + ProductDetail |
| AdminInventory "Low Stock" filter | Shows only low-stock products |
| Add to cart at max stock | `+` disabled; toast on forced exceed |
| ProductDetail quantity 3, stock 5 | Adds 3 (not 1) |
| Checkout with stale over-quantity cart | Blocked with clear message before RPC |
| Checkout success | Stock decremented; cart cleared |
| Deactivated product in cart | Blocked at checkout (after `place_order` hardening) |
| Admin cancels order (after `cancel_order`) | Stock restored |

### 9.3 Regression

- Existing 18 tests continue to pass
- Lint remains at 0 errors
- Production build succeeds
- Admin product CRUD unaffected
- Non-inventory admin pages unaffected

### 9.4 Live Validation (post-deploy)

```sql
-- Confirm no negative stock
SELECT id, name, stock FROM products WHERE stock < 0;

-- Confirm CHECK exists
SELECT conname, convalidated FROM pg_constraint
WHERE conname = 'products_stock_nonneg_check';
```

---

## 10. Implementation Plan (Suggested Order)

| Step | Work | Depends on |
|---|---|---|
| 1 | Create `constants/inventory.js` + unit tests | — |
| 2 | Fix `adminService.getInventory` filters + threshold alignment | Step 1 |
| 3 | Upgrade `AdminInventory.jsx` (filters, search, sort) | Step 2 |
| 4 | Fix `ProductDetail` quantity bug | Step 1 |
| 5 | Add stock caps to `cartService` + `CartContext` | Step 1 |
| 6 | Upgrade `Cart.jsx` UI (stock display, cap increment) | Step 5 |
| 7 | Add checkout pre-validation in `Checkout.jsx` | Step 5 |
| 8 | Storefront: `is_active` filter + ProductCard/Shop badges | Step 1 |
| 9 | Migration `011`: CHECK, `place_order` is_active, `cancel_order` | Steps 1–7 |
| 10 | Wire order cancel to `cancel_order` (AdminOrderDetail) | Step 9 |
| 11 | Documentation + Migration_History update | All |

**Estimated scope:** ~12–16 files touched, 1 new migration, 2–3 new test files.

---

## 11. Risks and Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Client stock caps bypassed by direct API calls | Low | `place_order` remains authoritative; server validates always |
| Stale cart stock vs live inventory | Medium | Pre-checkout re-fetch; show warnings in cart |
| `cancel_order` double-restore on repeated cancel | Medium | Idempotent cancel: only restore if status transition allowed |
| `is_active` filter hides products unexpectedly | Low | Admin sees all; storefront filter documented; admin toggle unchanged |
| Migration `011` alters `place_order` on live | Medium | Backup before apply; test on staging; change is additive check only |
| Threshold change affects dashboard counts | Low | Single constant; one place to update |
| Negative stock CHECK fails on existing data | Low | Pre-validate: `SELECT count(*) FROM products WHERE stock < 0` (expect 0) |
| Breaking AdminInventory during refactor | Low | Fix filters first (smallest change); incremental PRs |

---

## 12. Production Readiness Assessment (Post-WS1 Target)

| Criterion | Current | Target after WS1 |
|---|---|---|
| Admin can view/filter/update stock | Partial (filters broken) | ✅ Complete |
| Low-stock visibility | Partial (threshold bug) | ✅ Consistent |
| Out-of-stock handling (storefront) | Partial | ✅ All surfaces |
| Cart stock validation | ❌ | ✅ Client-capped |
| Checkout stock validation | Server only | ✅ Client preview + server |
| Stock restore on cancel | ❌ | ✅ via `cancel_order` |
| Negative stock prevention | ❌ | ✅ CHECK constraint |
| Inactive product checkout block | ❌ | ✅ in `place_order` |
| Test coverage for inventory | ❌ | ✅ Core helpers + cart caps |

---

## 13. Summary

Babees Place already has the **foundation** for inventory management: `products.stock`, admin stock editing, server-side checkout validation, and a dedicated Admin Inventory page. Workstream 1 closes the gaps between that foundation and a **complete system** by:

1. Fixing broken admin filters and threshold inconsistencies
2. Adding client-side stock validation in cart and checkout (UX layer)
3. Fixing the ProductDetail quantity bug
4. Surfacing low-stock and out-of-stock consistently
5. Hardening the database with a non-negative stock CHECK and `is_active` guard in `place_order`
6. Implementing `cancel_order` for stock restoration (canonical Phase 2 requirement)

No new inventory tables are required. One forward migration (`011`) and focused frontend changes deliver the full workstream without breaking existing functionality.

**STOP.** Design complete. Implementation deferred to Workstream 1 execution phase.
