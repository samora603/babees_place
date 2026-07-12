# Frontend — Technical Reference

Status: Starter content populated during Phase 0.
Source of truth: `frontend/` (verified: `npm run build` succeeds).

---

## 1. Stack
- React 18 + Vite 5, React Router 6, Tailwind CSS 3.
- UI libs: `react-hot-toast`, `react-icons`, `react-image-gallery`, `swiper`, `recharts`, `clsx`.
- Path alias `@ → src` (`vite.config.js`). Dev server port 5173.

## 2. Structure
```
src/
├── main.jsx                # providers: Auth → Cart → Wishlist → App (BrowserRouter)
├── App.jsx                 # routes (lazy-loaded)
├── components/{ui,layout,products,orders,auth}
├── pages/                  # public pages
│   └── admin/              # admin pages
├── context/{Auth,Cart,Wishlist}Context.jsx
├── hooks/                  # useDebounce, usePagination, useProducts (+ dead: useAuth/useCart/useWishlist)
├── services/               # Supabase data access
├── lib/                    # supabaseClient (+ re-export supabase.js; dead auth.js)
└── utils/{constants,helpers}.js
```

## 3. Routing (`App.jsx`)
- Public: `/`, `/shop`, `/shop/:idOrSlug`, `/login`, `/register`.
- Protected (`ProtectedRoute`): `/cart`, `/wishlist`, `/checkout`, `/orders`, `/orders/:id`, `/orders/:id/confirmation`, `/profile`.
- Admin (`AdminRoute` + `AdminLayout`): `/admin/dashboard|products|products/new|products/:id/edit|orders|orders/:id|users|inventory|pickup-locations|settings`.
- 404 catch-all.
- All routes are `React.lazy` + `Suspense` → good code splitting.

### ⚠️ Known routing/layout defects
- `Navbar` + `Footer` render **only** inside the `/` route element → every other page has no nav/footer (HIGH bug).
- Duplicate `<Route path="/">` (second is unreachable/dead).
- `pages/ProductsPage.jsx` is **not routed** and links to `/product/:id` (wrong path) — dead component.

## 4. State management
- React Context for Auth, Cart, Wishlist (appropriate for this size).
- ⚠️ Cart logic is duplicated between `CartContext` and the **unused** `hooks/useCart.js`, and the two disagree on pricing (`discountPrice` vs raw `price`).

## 5. Styling
- Design tokens in `tailwind.config.js` (brand gold palette, surface colors, Inter/Outfit fonts).
- Component classes in `index.css` (`.btn-primary`, `.btn-secondary`, `.card`, `.input`, `.section-container`, …).
- Consistent luxury dark theme.

## 6. UX states
- Loading (`Spinner`, `Skeleton`, `ProductCardSkeleton`) and empty states are generally present.
- ⚠️ Error states are undermined by services swallowing errors; no global Error Boundary.
- ⚠️ `/placeholder.png` is referenced as the image fallback but is **missing** from `public/` → broken images.

## 7. Tooling status
- Build: ✅ works.
- Lint: ❌ `npm run lint` fails — no ESLint config file exists (and it lints `dist/`).
- Tests: ❌ none.

## 8. Known issues → see `docs/audits/FRONTEND_AUDIT.md` and `Frontend_Health_Report.md`.
