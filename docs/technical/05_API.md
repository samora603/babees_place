# API / Data Access — Technical Reference

Status: Starter content populated during Phase 0.
Source of truth: `frontend/src/services/*.js`, `frontend/src/lib/*`.

---

## 1. Model

There is **no custom REST/Express backend**. All data access goes directly to Supabase (PostgREST + Auth + Storage + one RPC) through a thin **services layer**. A legacy `axios` instance (`services/api.js`) exists but is **unused/dead**.

```
pages / context / hooks → services/*.js → lib/supabaseClient (supabase-js) → Supabase
```

## 2. Supabase client
- `lib/supabaseClient.js` — creates the client from `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY` (anon key only).
- `lib/supabase.js` — re-exports the same client for import-path compatibility.
- ⚠️ No env-var validation; missing envs fail silently at runtime.

## 3. Services

| Service | Responsibility | Backing table(s) |
|---|---|---|
| `productService` | list/get products, derive categories | `products` |
| `cartService` | cart CRUD | `cart` (+ `products` join) |
| `wishlistService` | wishlist CRUD | `wishlist` (+ `products` join) |
| `orderService` | place order (RPC), map orders, history | `orders`, `order_items`, RPC `place_order` |
| `paymentService` | **stub** — insert/select payment record | `payments` (unverified) |
| `adminService` | stats, orders, users, products, categories, inventory, pickup locations | multiple |
| `userService` | profile + addresses | `profiles`, `addresses` (unverified) |
| `authService` | OTP/session helpers — **dead & broken (Markdown fences)** | Supabase Auth |

## 4. Conventions observed
- Services return a wrapped shape, commonly `{ data: { data, ... }, error }` (shapes are **inconsistent** across services — a refactor target).
- Checkout uses the atomic RPC `place_order`; a client-side fallback (`createOrderFromCart`) exists but is **insecure** (client-controlled totals) and should be removed.

## 5. Key calls (examples)
- Products: `supabase.from('products').select('*', { count: 'exact' })` with `ilike`/`eq`/`gte`/`lte` filters + `range()` pagination.
- Checkout: `supabase.rpc('place_order', { p_user_id })`.
- Admin stats: parallel `count`/`head` queries via `Promise.all`; revenue aggregated **client-side** (does not scale).

## 6. Known issues (see `docs/audits/FRONTEND_AUDIT.md`, `SUPABASE_AUDIT.md`)
- `productService` swallows errors (returns `error: null`) — failures look like empty results.
- `adminService.uploadImages` mis-destructures `getPublicUrl` (`publicURL` vs `data.publicUrl`).
- Inconsistent return shapes across services.
- Dead code: `services/api.js`, `services/authService.js`.
- Payments are a local stub; no server-side verification (needs an Edge Function).

## 7. Target conventions
- One consistent service return contract.
- All writes that affect money/inventory go through server-validated RPCs/Edge Functions.
- Errors propagate to the UI (no silent swallowing).
