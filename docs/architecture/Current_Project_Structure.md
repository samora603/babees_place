# Current Project Structure

Status: Generated during Phase 0 from the actual repository (evidence-based).
Excludes generated/tooling paths: `node_modules/`, `.git/`, `supabase/.temp/`, `supabase/.branches/`.

---

## Top level
```
babees_place/
├── .gitignore              # repaired in Phase 0 (was an empty directory)
├── README.md
├── docs/                   # documentation (see below)
├── frontend/               # React + Vite application
└── supabase/               # migrations + config (Supabase backend)
```
> `.github/` (CI) and `scripts/` are referenced in some docs but **do not exist yet** (planned for Phase 1).

## docs/
```
docs/
├── 00_PROJECT_VISION.md
├── 01_ARCHITECTURE.md
├── 03_Security.md
├── 10_Final_Checklist.md
├── 13_CODING_STANDARDS.md
├── AI_COLLABORATION.md
├── AUTOMATIONS.md
├── CHANGELOG.md
├── DECISIONS.md            # ADRs
├── ENGINEERING.md
├── NEXT_STEPS.md           # roadmap
├── PROJECT_MASTER_PLAN.md
├── architecture/
│   └── Current_Project_Structure.md   (this file)
├── audits/
│   ├── 01_Project_Audit.md            (index → superseded)
│   ├── PROJECT_AUDIT.md · SECURITY_AUDIT.md · FRONTEND_AUDIT.md
│   ├── DATABASE_AUDIT.md · SUPABASE_AUDIT.md · PERFORMANCE_AUDIT.md
│   ├── PRODUCTION_READINESS.md
│   └── (Phase 0) Phase0_Repository_Audit.md · Documentation_Audit.md ·
│       Dependency_Audit.md · Frontend_Health_Report.md · Supabase_Health_Report.md ·
│       Environment_Audit.md · Security_Baseline.md · Production_Readiness.md ·
│       Technical_Debt_Register.md · Phase0_Final_Report.md
├── technical/
│   ├── 02_Database.md · 04_Authentication.md · 05_API.md
│   ├── 06_Frontend.md · 07_Admin.md · 08_Deployment.md · 09_Testing.md
├── operations/   (empty — placeholder dir)
├── prompts/      (empty — placeholder dir)
├── references/   (empty — placeholder dir)
└── testing/      (empty — placeholder dir)
```
> Note: `04_Authentication.md` previously had a corrupted filename (embedded newline); fixed in Phase 0. The four empty `docs/*` subdirectories are untracked (Git does not store empty dirs) and are cleanup/placeholder candidates.

## frontend/
```
frontend/
├── .env                  # untracked + git-ignored (Phase 0); anon key only
├── .env.example          # added in Phase 0
├── .gitignore            # added in Phase 0
├── index.html
├── package.json · package-lock.json
├── postcss.config.js · tailwind.config.js · vite.config.js
├── skills-lock.json
├── .agents/              # AI tooling skill docs (40 files, tracked) — non-app material
├── .qodo/                # AI tool local state (untracked)
├── public/
│   ├── assets/images/{Background_image.jpeg, hero-bg.jpg}
│   └── hero_carousel/{hero1..hero4}.jpeg
│   └── (MISSING: placeholder.png — referenced by code)
└── src/
    ├── main.jsx · App.jsx · index.css
    ├── components/
    │   ├── auth/OtpInput.jsx                (dead — unused)
    │   ├── layout/{AdminLayout,AdminRoute,Footer,Hero,Navbar,ProtectedRoute}.jsx
    │   ├── orders/OrderStatusBadge.jsx
    │   ├── products/{ProductCard,ProductCardSkeleton,ProductGrid}.jsx
    │   └── ui/{Button,Modal,Pagination,QuantitySelector,Skeleton,Spinner,StarRating}.jsx
    ├── context/{AuthContext,CartContext,WishlistContext}.jsx
    ├── hooks/{useDebounce,usePagination,useProducts}.js
    │   └── (dead: useAuth.js, useCart.js, useWishlist.js)
    ├── lib/{supabaseClient.js, supabase.js}   (+ dead: auth.js)
    ├── pages/ (public) {Cart,Checkout,Home,Login,NotFound,OrderConfirmation,
    │   OrderDetail,Orders,ProductDetail,Profile,Register,Shop,Wishlist}.jsx
    │   └── (dead/unrouted: ProductsPage.jsx)
    │   └── admin/ {AdminDashboard,AdminInventory,AdminOrderDetail,AdminOrders,
    │       AdminPickupLocations,AdminProductForm,AdminProducts,AdminSettings,AdminUsers}.jsx
    ├── services/ {adminService,cartService,orderService,paymentService,
    │   productService,userService,wishlistService}.js
    │   └── (dead: api.js; dead+broken: authService.js)
    └── utils/{constants,helpers}.js
```
Counts: 18 component files, 23 page files (incl. admin), 9 service files.

## supabase/
```
supabase/
├── config.toml
├── .gitignore
└── migrations/
    ├── 001_schema_rls_place_order.sql        # profiles, orders, order_items, cart, RLS, place_order RPC
    └── 20260617042152_remote_schema.sql      # EMPTY (0 bytes) — schema not reproducible
```
> Tables used by the app but absent from migrations (remote-only, UNVERIFIED): `products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`. See `docs/technical/02_Database.md`.

## Legend of health flags
- **dead** = present but not imported/routed anywhere.
- **broken** = does not parse / references missing assets.
- **UNVERIFIED** = exists only on the live Supabase project; not in repo.
