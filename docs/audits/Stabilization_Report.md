# Stabilization & Bug Fix Report

**Phase:** Stabilization (pre–Milestone 5.3)  
**Date:** 2026-07-13  
**Scope:** Functional consistency, routing, cart UX, checkout → order reads, auth hardening  
**Status:** Complete — tests + build green

---

## Executive summary

Three known user-facing failures were confirmed and fixed:

1. **Collection “Add to Cart” felt broken** — cart context worked, but Navbar/badge lived only on Home and **toasts never rendered** (`<Toaster />` missing).
2. **Checkout → “Order not found”** — order creation succeeded; **read path failed** because PostgREST cannot embed `profiles` on `orders` (no FK `orders → profiles`).
3. **Add-to-cart inconsistency perception** — Home/Shop already shared `ProductCard` → `CartContext`; Product Detail was aligned (auth gate, await, busy state).

Additional high/medium defects from a full-app audit were fixed in the same pass. No new product features beyond stabilization UX (shared layout + floating cart button + visible toasts).

---

## SECTION 1 — Bugs found

| ID | Severity | Bug |
|---|---|---|
| S-01 | **Critical** | All `toast.*` calls invisible — `<Toaster />` never mounted |
| S-02 | **Critical** | Order Confirmation / Detail / My Orders / Admin order lists fail or empty because `profiles` embed on `orders` throws PGRST200 |
| S-03 | **High** | Navbar + Footer only on `/` — Shop, PDP, Cart, Orders had no chrome / cart badge |
| S-04 | **High** | Order pages mask API errors as “Order not found” / empty list (no `.catch`) |
| S-05 | **High** | Login can leave half-authenticated React state if profile load fails, then auto-redirect off `/login` |
| S-06 | **High** | Cart load race: in-flight `getCart` can overwrite cart after logout |
| S-07 | **Medium** | Cart page `+` called `addToCart` (success toast + loading flash) instead of `setQuantity` |
| S-08 | **Medium** | `cartService.addToCart` returned success when `userId`/`productId` missing |
| S-09 | **Medium** | Product Detail: no auth gate; fire-and-forget add; variation UI unused |
| S-10 | **Medium** | Protected/Admin routes did not preserve return URL (`state.from`) |
| S-11 | **Medium** | Signup always toasted full success even when email confirmation left session null |
| S-12 | **Medium** | Cart fetch failures presented as empty cart |
| S-13 | **Medium** | Missing `/placeholder.png` → broken images |
| S-14 | **Medium** | Admin users search UI ignored `search` param |
| S-15 | **Medium** | Analytics recent orders / activity also used broken `profiles` embeds |
| S-16 | **Low** | ProductCard did not await add / disable while adding |
| S-17 | **Low** | `ensureProfile` insert race with DB trigger not retried via re-fetch |
| S-18 | **Low** | Logout errors not surfaced |

### Deferred (documented, not blocking 5.3)

| ID | Severity | Bug | Notes |
|---|---|---|---|
| D-01 | Medium | No guest cart / merge-on-login | DB cart only; requires product decision |
| D-02 | Medium | Profile email update does not sync `auth.users` email | Needs Auth API + confirmation flow |
| D-03 | Low | Wishlist realtime channel unfiltered | Noisy refetch only |
| D-04 | Low | Product variations not persisted on cart lines | Schema gap |

---

## SECTION 2 — Root causes

### S-01 — Invisible toasts
`react-hot-toast` was a dependency and called from CartContext, ProductCard, Checkout, etc., but **no `<Toaster />` component** existed under the React tree (`main.jsx`).

### S-02 / S-15 — Order not found
Checkout correctly called `place_order` RPC (returns UUID) and navigated to `/orders/:id/confirmation`.  
`getOrder` / `getMyOrders` / admin / analytics selected:

```sql
profiles (full_name, email, phone)
```

`orders.user_id` FKs to **`auth.users`**, not **`public.profiles`**. PostgREST requires a direct FK for embeds → **PGRST200**. Pages had no `.catch()`, so `order` stayed `null` → UI text **“Order not found.”**

### S-03 — Collection badge / feedback
`App.jsx` only wrapped Navbar/Footer around the `/` route element. Shop and Product Detail updated `CartContext.itemCount`, but nothing visible displayed it.

### S-05 — Half login
`applyAuthSession` set `user` before verifying profile; on failure `login` threw but `user` remained, triggering the post-login redirect effect.

### S-06 — Cart race
`loadCartForUser` had no sequence/generation guard; logout cleared cart, then an older promise could `setCart` again.

---

## SECTION 3 — Affected files

### Added
| File | Purpose |
|---|---|
| `frontend/src/services/profileLookup.js` | Attach profiles via separate query |
| `frontend/src/services/profileLookup.test.js` | Unit tests |
| `frontend/src/components/layout/StorefrontLayout.jsx` | Shared Navbar/Footer/Outlet |
| `frontend/src/components/layout/FloatingCartButton.jsx` | Floating cart count FAB |
| `frontend/public/placeholder.png` | Image fallback asset |
| `docs/audits/Stabilization_Report.md` | This report |

### Modified
| File | Change |
|---|---|
| `frontend/src/main.jsx` | Mount `<Toaster />` |
| `frontend/src/App.jsx` | StorefrontLayout; admin routes first |
| `frontend/src/services/orderService.js` | Drop profiles embed; enrich via lookup |
| `frontend/src/services/adminService.js` | Same + users search |
| `frontend/src/services/analyticsService.js` | Same for recent orders / activity |
| `frontend/src/services/cartService.js` | Missing IDs → error |
| `frontend/src/context/CartContext.jsx` | Seq guard, soft reload, errors, consistent auth toast |
| `frontend/src/context/AuthContext.jsx` | Atomic session+profile, return URL, logout errors, signup shape |
| `frontend/src/components/layout/ProtectedRoute.jsx` | `state.from` |
| `frontend/src/components/layout/AdminRoute.jsx` | `state.from` |
| `frontend/src/components/products/ProductCard.jsx` | Await + busy state |
| `frontend/src/pages/ProductDetail.jsx` | Auth gate, await, busy state |
| `frontend/src/pages/Cart.jsx` | `setQuantity` increment; cart error UI |
| `frontend/src/pages/Orders.jsx` | Error + retry |
| `frontend/src/pages/OrderDetail.jsx` | Error vs not-found |
| `frontend/src/pages/OrderConfirmation.jsx` | Error vs not-found |
| `frontend/src/pages/Register.jsx` | Email-confirm messaging |
| `frontend/src/services/orderService.test.js` | Profile lookup mocks |
| `frontend/src/services/analyticsService.test.js` | Profile lookup mocks |
| `frontend/src/test/routing.test.jsx` | Register button query with Navbar present |

---

## SECTION 4 — Fixes implemented

1. **Toaster** at app root — success/error feedback visible site-wide.
2. **StorefrontLayout** — Navbar, Footer, FloatingCartButton on all customer routes.
3. **profileLookup** — orders fetched without `profiles` embed; profiles attached in a second query by `user_id`.
4. **Order UI error states** — distinguish load failure vs true not-found; retry where useful.
5. **CartContext** — load sequence IDs; mutation reloads without full-page skeleton; surface fetch errors.
6. **Auth hardening** — no React `user` without profile; rollback + signOut on profile failure; post-login return to `state.from`; signup returns `{ user, session }`.
7. **UX alignment** — ProductCard / PDP await add; Cart `+` uses `setQuantity`; floating cart FAB when `itemCount > 0`.
8. **placeholder.png** added under `public/`.
9. **Admin user search** wired to `ilike` on name/email.

**No database migration** — enrichment is application-side. Optional future migration: FK `orders.user_id → profiles(id)` would allow native embeds again.

---

## SECTION 5 — Regression checklist

- [x] `npm test` — all suites pass
- [x] `npm run build` — succeeds
- [x] Order service unit tests (place / get / reorder)
- [x] Analytics recent orders + activity
- [x] Routing smoke (login / register / 404) with shared Navbar
- [x] Checkout confirmation path no longer depends on broken embed
- [x] Cart badge available via Navbar on Shop/PDP + floating button

---

## SECTION 6 — Manual testing checklist

### Cart consistency
1. Sign in → Home → Add to Cart → toast + navbar badge + FAB update.
2. Collection (`/shop`) → Add to Cart → same feedback.
3. Product Detail → Add to Cart (qty > 1) → cart shows correct quantity.
4. Guest on PDP → toast + redirect to login with return path.

### Checkout → confirmation
5. Cart → Checkout (pickup or delivery) → place order → **Order Confirmed** shows items/total (not “not found”).
6. Open order detail from confirmation → loads.
7. My Orders lists the new order.
8. Express checkout (if prefs set) → same confirmation success.

### Auth / layout
9. Visit `/shop` logged out → Navbar visible.
10. Hit `/cart` logged out → login → after login return to `/cart` (or intended path).
11. Logout → cart clears; no stale items flash back.

### Admin
12. Admin Orders list shows customer names.
13. Admin Order Detail loads customer email/name.
14. Dashboard Recent Orders / Activity show customer names when available.

---

## SECTION 7 — Final assessment

**Is the application stable enough to continue to Milestone 5.3?**

**Yes**, with the following caveats:

- Critical cart feedback and order-read regressions are fixed; automated tests and production build pass.
- Deferred items (guest cart, auth email sync, variation persistence) are non-blocking for recommendations work but should stay on the backlog.
- Recommend a short manual smoke of checkout confirmation on the linked Supabase project before starting 5.3.

**Do not start Milestone 5.3 until** the manual checklist above (especially steps 5–8) is exercised once on a live session.

---

## Test / build results (this pass)

```
Test Files  43 passed
Tests       252 passed
Build       vite build — success
```

---

## Changelog for QA log continuity

| Date | Entry |
|---|---|
| 2026-07-13 | Initial stabilization pass: Toaster, StorefrontLayout, floating cart, profileLookup for orders, cart/auth hardening, order page error states. |
