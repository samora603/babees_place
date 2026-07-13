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
├── components/{ui,layout,products,orders,checkout,profile,auth}
├── pages/                  # public pages
│   └── admin/              # admin pages
├── context/{Auth,Cart,Wishlist}Context.jsx
├── hooks/                  # useDebounce, usePagination, useProducts (+ dead: useAuth/useCart/useWishlist)
├── models/                 # domain mappers + validation (address, preferences, analytics, …)
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

## 8. Customer profile (Phase 2 WS5 — Milestone 5.1)

### Profile page (`/profile`)
Three reusable sections via `components/profile/`:
- **Personal Information** — `PersonalInfoForm` (name, phone; email read-only from auth).
- **Address Book** — `AddressBook` + `AddressForm` (CRUD, default badge, delete confirmation modal).
- **Account Preferences** — `AccountPreferencesForm` (fulfillment default, pickup location, marketing/SMS flags — storage only).

Data loaded via `customerProfileService.getProfileBundle()` (parallel addresses + preferences).

### Checkout address integration
`CheckoutDeliverySection` supports three delivery modes when the customer has saved addresses:
1. **saved** — pick from address book; maps via `addressToCheckoutDelivery()` to existing order JSONB.
2. **new** — full address form with optional “Save to my account”.
3. **once** — legacy inline fields (line1/line2/city/phone/notes) without persisting.

Checkout bootstrap applies preference defaults (`preferredFulfillment`, `preferredPickupLocationId`).

### Services
| Service | Tables |
|---|---|
| `addressService.js` | `customer_addresses` |
| `customerProfileService.js` | `customer_preferences` (+ bundle with addresses) |

Business logic and validation live in `models/address.js` and `models/preferences.js`.

### Faster checkout (Phase 2 WS5 — Milestone 5.2)

Returning customers with saved preferences may use **express checkout**:

| Component / Service | Role |
|---|---|
| `models/fasterCheckout.js` | Eligibility rules, express fulfillment builder, reorder summaries |
| `checkoutService.js` | Bootstrap data, express order placement |
| `orderService.reorder()` | Add prior order items to cart (merge, skip unavailable) |
| `ExpressCheckoutPanel` | One-click checkout on `/checkout` |
| `CartExpressHint` | Sidebar banner when express is available |
| `ReorderButton` | Order detail action → cart |

Express requires valid cart + configured preferences (pickup location or default delivery address). Standard checkout from 5.1 remains available below the express panel.

## 9. Known issues → see `docs/audits/FRONTEND_AUDIT.md` and `Frontend_Health_Report.md`.
