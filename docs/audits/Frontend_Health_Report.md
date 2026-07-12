# Phase 0 — Frontend Health Report

Auditor: Principal Frontend Engineer
Date: 2026-07-12
Scope: `frontend/` (React 18 + Vite 5 + Tailwind 3 + React Router 6).
Build: ✅ `npm run build` succeeds (verified). Lint: ❌ `npm run lint` fails (no ESLint config).
Cross-reference: `docs/audits/FRONTEND_AUDIT.md` (deeper analysis), `docs/technical/06_Frontend.md`.

---

## 1. Health summary
| Check | Result |
|---|---|
| Broken imports | ✅ None (all external imports resolve; build passes) |
| Circular dependencies | ✅ None found (services do not import contexts; contexts→services only) |
| Duplicate components | 🟡 Cart logic duplicated (`CartContext` vs unused `hooks/useCart.js`) |
| Inconsistent naming | 🟡 Brand "Babis" vs "Babees"; mixed service return shapes |
| Dead components | ❌ `ProductsPage.jsx`, `OtpInput.jsx` |
| Dead hooks | ❌ `useAuth.js`, `useCart.js`, `useWishlist.js` |
| Dead routes | ❌ Duplicate `/` route (unreachable) |
| Broken files | ❌ `services/authService.js` (Markdown fences → invalid JS; unused) |
| Missing assets | ❌ `/placeholder.png` referenced but absent |

## 2. Broken imports / circular deps
- **Broken imports:** none — the production build transforms 1,013 modules successfully, which would fail on an unresolved import in the live graph. (Dead files with bad content are simply not in the graph.)
- **Circular dependencies:** none detected. Dependency direction is `pages → context/hooks → services → lib`. `WishlistContext` imports `AuthContext` (one-way). No service imports a context (verified by grep).

## 3. Dead code inventory (evidence: import search returns no references)
| Path | Type | Note |
|---|---|---|
| `src/pages/ProductsPage.jsx` | page | Not routed in `App.jsx`; links to wrong `/product/:id` path |
| `src/components/auth/OtpInput.jsx` | component | OTP flow never wired |
| `src/hooks/useAuth.js` | hook | Re-export of context hook; redundant |
| `src/hooks/useCart.js` | hook | Duplicate cart logic; disagrees on pricing (`price` vs `discountPrice`) |
| `src/hooks/useWishlist.js` | hook | Unused |
| `src/lib/auth.js` | lib | Auth helpers; app uses `AuthContext` |
| `src/services/api.js` | service | Legacy axios; unused |
| `src/services/authService.js` | service | **Broken** (invalid JS) + unused |

**Status:** DOCUMENTED, not deleted (Phase 0 rule). All are Phase 1 removal candidates once confirmed no external/planned use.

## 4. Routing / layout defects (HIGH)
- `Navbar`/`Footer` render **only** inside the `/` route element (`App.jsx:50-59`); all other pages render with no chrome. Fix: shared `<Layout>` with `<Outlet/>`.
- Duplicate `<Route path="/">` (`App.jsx:50` and `:61`) — second is dead.
- Otherwise routing is well-structured: lazy loading + `Suspense`, protected/admin route groups, nested admin layout, 404 catch-all.

## 5. Reliability defects
- **Error swallowing:** `productService` catches errors and returns `error: null` — UI cannot show error states; failures look like empty results. (MEDIUM)
- **No Error Boundary** — a render error blanks the whole app. (MEDIUM)
- **No env validation** in `lib/supabaseClient.js` — missing envs fail silently. (MEDIUM)
- **Missing `/placeholder.png`** — broken fallback images in cart/wishlist/orders. (MEDIUM)
- **`getPublicUrl` bug** in `adminService.uploadImages` (`publicURL` vs `data.publicUrl`) → undefined image URLs. (MEDIUM)

## 6. Tooling
- ✅ Vite build config clean (`@` alias, react plugin).
- ✅ Tailwind config with design tokens; `index.css` component layer.
- ❌ **No ESLint config file** → `npm run lint` errors out and even tries to lint `dist/`. Add config + `.eslintignore`. (HIGH — quality gate)
- ❌ No tests / test framework.
- 🟡 28 `console.*` statements; no client logger.

## 7. Positives (keep)
- Clean, modular structure; largest file 264 lines (no oversized components).
- Good code splitting (per-route chunks; recharts/swiper isolated).
- Consistent design system and reusable UI kit.
- Memoized cart derivations (`useMemo`/`useCallback`).

## 8. Recommendations (priority)
1. Add shared layout; remove duplicate `/` route (HIGH).
2. Add ESLint config + `.eslintignore`; wire into CI (HIGH).
3. Delete dead files (§3) and unused deps (`react-image-gallery`, `axios`) (Medium).
4. Stop swallowing errors; add Error Boundary + env validation (Medium).
5. Add `/placeholder.png`; fix `getPublicUrl` (Medium).
6. Consolidate cart to a single source (`CartContext`) (Medium).
7. Normalize service return shapes; remove `console.*`; consider TypeScript (Low/Med).

## 9. Frontend health score: **6/10** (unchanged by Phase 0 — issues documented, code left intact per rules).
