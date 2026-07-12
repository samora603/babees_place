# Frontend Audit — Babees Place

Auditor role: Principal Frontend Engineer
Date: 2026-07-12
Scope: `frontend/` (React 18 + Vite 5 + Tailwind 3 + React Router 6).
Build status: `npm install` + `npm run build` **succeed** (verified; 1,013 modules, built in ~14s).
Lint status: `npm run lint` **fails** — no ESLint config file exists (verified).

---

## Summary score: 6 / 10

Clean layered architecture, good use of lazy loading/code splitting, a consistent design system, and reasonable component sizes (largest file 264 lines). Held back by a **site-wide layout bug (no navbar/footer off the home page)**, error-swallowing services, duplicated cart logic, dead/broken files, a missing image asset, and no tests or lint.

---

## 1. Architecture & organization
Layering matches the documented design (`docs/01_ARCHITECTURE.md`):
```
pages/ → context/ + hooks/ → services/ → lib/supabaseClient → Supabase
components/ (ui, layout, products, orders, auth)   utils/ (helpers, constants)
```
- Path alias `@ → src` configured in `vite.config.js`. ✅
- Services isolate all Supabase access. ✅
- Contexts (`Auth`, `Cart`, `Wishlist`) provide global state; providers nested in `main.jsx`. ✅
- File sizes are healthy — no component is oversized (see line-count table in PROJECT_AUDIT). ✅

## 2. Routing (`App.jsx`) — has defects
- ✅ Lazy-loaded routes, `Suspense` fallback spinner, protected + admin route groups, nested admin layout, 404 catch-all.
- ❌ **Layout bug (HIGH):** `Navbar` and `Footer` are rendered **only inside the `/` route element** (`App.jsx:50-59`). Every other public/protected page (`/shop`, `/login`, `/cart`, `/orders`, product detail, etc.) renders with **no navigation bar and no footer** — confirmed: `Navbar`/`<Footer` appear only in `App.jsx`, no page renders them itself. This breaks navigation across the entire site. Fix: introduce a shared `<Layout>` (Outlet-based) wrapping the public/protected route groups.
- ❌ **Dead duplicate route (LOW):** two `<Route path="/">` entries (`App.jsx:50` and `:61`); the second is unreachable.

## 3. State management
- Context API is appropriate for this app size. ✅
- ⚠️ **Duplicate cart implementations:** `context/CartContext.jsx` **and** `hooks/useCart.js` both fetch/derive cart state. They disagree on pricing — the context uses `discountPrice ?? price` (`CartContext.jsx:9-13`) while the hook uses raw `product.price` (`useCart.js:43`). The hook is unused (not imported), so it is dead code that will silently rot. Delete it.
- ⚠️ `AuthContext` does profile fetch on init, `onAuthStateChange`, and login — solid, but `fetchProfile` runs on every auth event and there is a post-login redirect `useEffect` reading `window.location.pathname` (fragile vs `useLocation`).

## 4. Data fetching, loading & error states
- Loading states: present in most pages (`Spinner`, skeletons `ProductCardSkeleton`/`Skeleton`). ✅
- Empty states: present (cart, checkout, product list). ✅
- ❌ **Error swallowing (MEDIUM):** `productService` catches errors and returns `error: null` with empty data (`productService.js:18-29, 35-43`). The UI can therefore never distinguish "no products" from "query failed" — real failures render as empty states. Errors should propagate so pages can show an error state.
- No global **Error Boundary** — a render error anywhere blanks the app.

## 5. Components / UI / design system
- Reusable UI kit: `Button`, `Modal`, `Pagination`, `QuantitySelector`, `Skeleton`, `Spinner`, `StarRating`. ✅
- Design tokens well defined in `tailwind.config.js` (brand gold palette, surface colors, fonts) and component classes in `index.css` (`.btn-primary`, `.card`, `.input`, …). ✅ Consistent luxury dark theme.
- `Button` uses `clsx` + variant map. ✅

## 6. Dead / orphan / broken files (technical debt)
| File | Problem |
|---|---|
| `src/services/authService.js` | Contains Markdown ``` fences inside `.js` → invalid JS; **unused** |
| `src/services/api.js` | Legacy axios instance; **unused** (no `services/api` imports) |
| `src/lib/auth.js` | Auth helpers; **unused** (app uses `AuthContext`) |
| `src/hooks/useAuth.js` | Just re-exports context hook; redundant |
| `src/hooks/useCart.js` | Duplicate cart logic, inconsistent pricing; **unused** |
| `src/hooks/useWishlist.js` | **Unused** |
| `src/pages/ProductsPage.jsx` | Not routed; links to `/product/:id` but real route is `/shop/:idOrSlug` → broken |
| `src/components/auth/OtpInput.jsx` | **Unused** — OTP auth is not wired into Login/Register |

## 7. Missing assets / runtime bugs
- ❌ `/placeholder.png` is referenced as the image fallback in `CartContext`, `orderService.mapOrder`, `helpers.getPrimaryImage`, etc., but **does not exist** in `public/`. Missing/failed product images render broken across cart, wishlist, and orders.
- ❌ `adminService.uploadImages` destructures `{ publicURL }`; supabase-js v2 returns `{ data: { publicUrl } }` → uploaded image URLs are `undefined`.

## 8. Responsive design & accessibility
- Responsive: Tailwind responsive utilities are used (`sm:`, `lg:`, grids). Generally responsive. ✅ (Not device-tested here.)
- Accessibility gaps: heavy use of styled `div`s; not all interactive elements are semantic buttons/links; icon-only controls lack consistent `aria-label`s; color-contrast on gold-on-black not formally checked. No systematic a11y pass. ⚠️

## 9. Performance (frontend)
See PERFORMANCE_AUDIT for detail. Highlights: code-splitting works; main bundle ~392 kB (114 kB gzip); `AdminDashboard` ~387 kB (recharts, lazy — good); `getCategories` fetches the entire products table on every call; realtime subscriptions trigger full cart/wishlist re-fetches.

## 10. React best-practice notes
- `useProducts` depends on `JSON.stringify(params)` (`useProducts.js:23`) — works but a memoized params object is cleaner.
- 28 `console.*` calls should be removed/replaced with a logger before production.
- No prop-types/TypeScript; `package.json` includes `@types/react` but the code is plain JSX — consider migrating to TypeScript for the "production-grade" goal.

## 11. Recommendations (priority)
1. **Add a shared layout** so navbar/footer appear on all pages; remove the duplicate `/` route (HIGH).
2. Delete dead files (§6); fix or remove `authService.js`.
3. Add `/placeholder.png`; fix `getPublicUrl` usage.
4. Stop swallowing errors in services; add an Error Boundary and real error states.
5. Consolidate cart state to a single source (`CartContext`).
6. Add an ESLint config (+ `.eslintignore` for `dist/`) so `npm run lint` works; wire it into CI.
7. Introduce input validation (Zod) and a client logger; remove `console.*`.
8. Add a test setup (Vitest + Testing Library) — currently zero tests.
