# Phase 2 — Workstream 2: Product Management — Audit & Design

**Status:** Audit + design only — no implementation  
**Date:** 2026-07-12  
**Prerequisite:** Phase 2 Workstream 1 complete (migrations `001`–`011` applied; inventory production-ready)  
**Reference design (WS1):** `docs/audits/Phase2_Workstream1_Inventory_Design.md`

---

## 1. Executive Summary

Babees Place has a **functional but incomplete** product management layer. Core admin CRUD (create/read/update) works against Supabase for basic fields, categories use the canonical FK model (`category_id` → `categories`), and storage upload to the `products` bucket is implemented. However, several user-facing and admin flows are **broken or partial**: slug-based routing, featured merchandising, Home category links, image management on edit, category admin UI, product deletion, and storefront visibility filtering.

This document audits the current state across database, frontend, storage, validation, UX, and tests, then proposes a phased implementation plan for a **production-ready product management system** without modifying code in this workstream.

---

## 2. Step 1 — Database Audit

### 2.1 Current Schema (post-011, live)

#### `products`

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` | PK `(id)` since 008 |
| `name` | text | NO | — | |
| `slug` | text | YES | — | No UNIQUE constraint; non-unique index only |
| `description` | text | YES | — | Renamed from `"Description"` in 008 |
| `price` | numeric | YES | — | Not `numeric(12,2) NOT NULL` per canonical |
| `discount_price` | numeric(12,2) | YES | — | Added 002 |
| `stock` | integer | NO | `0` | CHECK `>= 0` since 011 |
| `image_url` | text | YES | — | Legacy single image; superseded by `images` jsonb |
| `images` | jsonb | NO | `'[]'` | Gallery array `[{ url, isPrimary }]` |
| `category_id` | uuid | YES | — | FK → `categories(id)` validated (009) |
| `category` | text | YES | — | **Deprecated** denormalized text (001 baseline) |
| `featured` | boolean | YES | `false` | Not filtered on storefront |
| `is_active` | boolean | NO | `true` | Filtered in `productService` (WS1); not in RLS |
| `created_at` | timestamp | YES | `now()` | Still `timestamp without time zone` |
| `updated_at` | timestamptz | NO | `now()` | **Live only** — ad-hoc hotfix in WS3; absent from migration 002 |

#### `categories`

| Column | Type | Null | Default | Notes |
|---|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `name` | text | NO | — | |
| `slug` | text | YES | — | No UNIQUE constraint |
| `created_at` | timestamp | YES | `now()` | |

**Live data note:** 0 categories exist; 1 product has orphan `category_id = NULL` with legacy `category = 'instruments'`.

### 2.2 Constraints & Indexes

| Object | Table | Status |
|---|---|---|
| `products_pkey` | products | PK `(id)` |
| `products_category_id_fkey` | products | FK → categories, ON DELETE SET NULL, **validated** |
| `products_stock_nonneg_check` | products | CHECK `stock >= 0`, **validated** (011) |
| `idx_products_category_id` | products | B-tree (010) |
| `idx_products_is_active` | products | B-tree (010) |
| `idx_products_slug` | products | B-tree, **non-unique** (010) |
| `idx_products_search` | products | GIN FTS on name+description (010) |
| Product FKs from cart/wishlist/order_items | — | NOT VALID (009) — manual validate pending |

**Missing vs canonical:**

- `products.slug` UNIQUE
- `categories.slug` UNIQUE
- `price NOT NULL DEFAULT 0`, `numeric(12,2)`
- `created_at` / `updated_at` as `timestamptz NOT NULL`
- Optional: `price >= 0` CHECK, `discount_price <= price` CHECK
- Drop deprecated `products.category` text column (gated)
- No SKU column (not in canonical schema; **out of scope**)

### 2.3 RLS

| Table | Policies | Gap |
|---|---|---|
| `products` | Public SELECT (`true`); admin ALL via `products_write_admin` | Inactive products visible at DB layer; app filters `is_active` only |
| `categories` | Public SELECT; admin ALL via `categories_modify_admin` | Adequate for WS2 |

### 2.4 Storage (006)

| Item | Configuration |
|---|---|
| Bucket | `products`, `public = true` |
| Read | `products_public_read` — any object in bucket |
| Write | Admin-only insert/update/delete via `is_admin()` |
| Path convention | `products/{productId}/{filename}` |

### 2.5 Database Technical Debt

| ID | Item | Severity |
|---|---|---|
| DB-1 | `products.updated_at` not in migration 002 (live hotfix only) | Medium |
| DB-2 | Deprecated `products.category` text column retained | Low |
| DB-3 | `slug` non-unique on products and categories | Medium |
| DB-4 | Timestamp types not `timestamptz` | Low |
| DB-5 | `price` nullable without CHECK | Low |
| DB-6 | RLS does not filter inactive products | Low (app-layer workaround exists) |
| DB-7 | No orphan cleanup when product deleted (storage objects) | Medium |
| DB-8 | NOT VALID product FKs on cart/wishlist/order_items | Low |

---

## 3. Step 2 — Frontend Audit

### 3.1 What Exists

| Feature | Location | Status |
|---|---|---|
| Admin product list | `AdminProducts.jsx` | ✅ Search, pagination (20/page), active toggle, stock display |
| Admin create/edit | `AdminProductForm.jsx` | ✅ Basic fields, category select, featured/active, image picker |
| Admin inventory | `AdminInventory.jsx` | ✅ Separate stock view (WS1) |
| Product read (storefront) | `productService.js` | ✅ List, detail, categories, filters |
| Product write (admin) | `adminService.js` | ✅ create/update/delete, uploadImages, category CRUD |
| Shop catalog | `Shop.jsx` | ✅ Filters, sort, pagination, in-stock filter |
| Product detail | `ProductDetail.jsx` | ✅ Display, cart add (WS1 stock validation) |
| Home merchandising | `Home.jsx` | ⚠️ Partial — wrong data source for "featured" |
| Wishlist links | `Wishlist.jsx` | ⚠️ Uses slug in URL |

### 3.2 What Is Partially Implemented

| Feature | Gap |
|---|---|
| **Categories** | Service CRUD exists; **no admin UI**; 0 categories on live |
| **Featured products** | Admin checkbox persists `featured`; Home shows **newest 8**, not `featured=true` |
| **Slug routing** | `getProduct()` supports slug fallback (admin edit only); `ProductDetail` uses UUID-only `getProductById` |
| **Image upload** | Works on create; edit has no preview, merge, delete, or primary selection |
| **Product delete** | `deleteProduct()` in service; **no UI**; only soft-deactivate via `is_active` |
| **Category display** | FK embed used but legacy `category` text fallback everywhere |
| **ProductDetail gallery** | Thumbnail clicks set `activeImage` but main image ignores it |
| **Shop URL state** | Only `page` synced to URL; category/search/sort lost on refresh/share |

### 3.3 What Is Broken

| ID | Issue | Files |
|---|---|---|
| B-1 | Home category links pass **name**, Shop filters by **UUID** | `Home.jsx:138`, `Shop.jsx:67` |
| B-2 | ProductCard/Wishlist link to `/shop/{slug}` but detail page only loads by UUID | `ProductCard.jsx:47`, `ProductDetail.jsx:32`, `Wishlist.jsx:28` |
| B-3 | "Featured Products" section ignores `featured` column | `Home.jsx:27`, `productService.js` |
| B-4 | Image upload errors silently ignored on save | `AdminProductForm.jsx:68-77` |
| B-5 | Edit mode overwrites entire `images` array; no existing image UI | `AdminProductForm.jsx` |
| B-6 | ProductDetail gallery non-functional | `ProductDetail.jsx:99-107` |
| B-7 | Debug Supabase query left in Home | `Home.jsx:61-70` |

### 3.4 Hooks

| Hook | Used? |
|---|---|
| `useDebounce` | ✅ Shop search |
| `usePagination` | ❌ Exists but unused |
| Product-specific hooks | ❌ None (`useProduct`, `useCategories`, etc.) |

### 3.5 Category Pages

**None.** Categories appear as Shop filter dropdown, Home chips (broken), and admin form select. No `/categories/:slug` landing page.

---

## 4. Step 3 — Storage Audit

### 4.1 Current Flow

```
AdminProductForm → FormData(files) → adminService.uploadImages(productId, formData)
  → supabase.storage.from('products').upload(`products/{id}/{filename}`, { upsert: true })
  → getPublicUrl(path) → { url: publicUrl }
  → updateProduct(productId, { images: [{ url, isPrimary }] })
```

### 4.2 What Works

- Bucket exists on live (created in 006)
- Public read for storefront image display
- Admin-only write (RLS + `is_admin()`)
- `upsert: true` allows re-upload same filename
- `getPrimaryImage()` helper resolves `isPrimary` flag or first image

### 4.3 Gaps

| ID | Gap | Impact |
|---|---|---|
| ST-1 | **No image deletion** from storage when removed from product | Orphan storage objects |
| ST-2 | **No cleanup** when product deleted | Orphan storage objects |
| ST-3 | **No file type/size validation** client-side | Bad uploads possible |
| ST-4 | **No filename sanitization** | Special chars may break paths |
| ST-5 | Edit replaces all images instead of merge | Data loss on partial re-upload |
| ST-6 | Legacy `image_url` column still referenced as fallback | Dual image model confusion |
| ST-7 | No storage usage reporting / orphan scan | Operational blind spot |
| ST-8 | Upload errors not surfaced to admin | Silent failure |

### 4.4 Recommended Storage Architecture (design)

```
products/{productId}/
  ├── {uuid}.{ext}          ← immutable filenames (avoid upsert collisions)
  └── ...

products.images jsonb:
  [{ "url": "...", "path": "products/...", "isPrimary": true, "alt": "..." }]

On delete product:
  1. List storage objects under products/{id}/
  2. Delete objects
  3. Delete DB row (or soft-delete)
```

---

## 5. Step 4 — Validation Audit

### 5.1 Current Validation

| Field | Admin form | Service layer | Database |
|---|---|---|---|
| `name` | HTML `required` | — | NOT NULL |
| `description` | HTML `required` | — | nullable |
| `price` | `required`, `min=0` | `Number()` coercion | nullable |
| `discount_price` | `min=0` | optional Number | nullable |
| `stock` | `required`, `min=0` | WS1 `updateStock` check | CHECK `>= 0` |
| `category_id` | optional select | — | FK validated |
| `is_active` | checkbox | WS1 cart/checkout | — |
| `featured` | checkbox | — | — |
| `slug` | **not in form** | — | no UNIQUE |
| `images` | file picker only | — | jsonb default `[]` |
| SKU | N/A | N/A | N/A |

### 5.2 Missing Validation

| Rule | Where needed |
|---|---|
| `discount_price < price` when set | Admin form + optional DB CHECK |
| `price > 0` for active products | Admin form |
| Slug format (`^[a-z0-9-]+$`) + uniqueness | Admin form + DB UNIQUE |
| Auto-generate slug from name | Admin create flow |
| Image MIME type whitelist (jpeg/png/webp) | Client + optional storage policy |
| Image max size (e.g. 5 MB) | Client |
| Category name/slug required on category CRUD | Category admin (new) |
| Prevent delete category with products (or SET NULL) | Service + confirm |
| Duplicate product name warning | Admin UX (non-blocking) |

### 5.3 Inventory Validation (WS1 — complete)

Cart/checkout stock and `is_active` validation implemented in WS1. Product form stock field aligns with DB CHECK.

---

## 6. Step 5 — UX Audit

### 6.1 Admin UX — Present

| Feature | Rating | Notes |
|---|---|---|
| Product list + search | ✅ Good | 20/page pagination |
| Create/edit form | ⚠️ Adequate | Single-page, no sections collapse |
| Active/inactive toggle | ✅ Good | Instant on list; no confirm |
| Featured checkbox | ⚠️ Misleading | No storefront effect |
| Stock in list | ✅ Good | Low-stock highlight (WS1) |
| Toast feedback | ✅ Good | Success/error on save |
| Inventory page | ✅ Good | WS1 filters work |
| Loading states | ✅ Good | Spinners on list |

### 6.2 Admin UX — Missing

| Feature | Priority |
|---|---|
| **Category management page** | P0 |
| **Delete product** with confirm dialog | P1 |
| **Image gallery manager** (preview, delete, set primary, reorder) | P0 |
| **Slug field** with auto-generate + preview URL | P1 |
| **Featured filter** on admin list | P2 |
| **Category/status/featured filters** on admin list | P2 |
| **Bulk actions** (activate/deactivate, delete) | P3 |
| **Product preview** (open storefront link) | P2 |
| **Confirm on deactivate** | P3 |
| **Empty states** (no products, no categories) | P2 |
| **Field-level error mapping** from Supabase | P2 |
| **Sort columns** on admin list | P2 |
| **Duplicate product** action | P3 |

### 6.3 Storefront UX — Issues

| Issue | Priority |
|---|---|
| Featured section shows wrong products | P0 |
| Category chips on Home broken | P0 |
| Slug URLs 404 on product detail | P0 |
| ProductDetail gallery broken | P1 |
| Shop filters not in URL (share/bookmark) | P2 |
| No category landing pages | P3 |
| Cosmetic variations/FAQs/ratings with no admin source | P3 (remove or defer) |

---

## 7. Step 6 — Test Audit

### 7.1 Existing Tests (48 total)

| Area | Tests | Product coverage |
|---|---|---|
| Inventory constants | 10 | Stock helpers only |
| Inventory validation | 10 | Cart/checkout, not CRUD |
| Migration 011 | 4 | Inventory SQL only |
| Inventory flow | 6 | Quantity/cart, not product CRUD |
| Helpers | 12 | `getPrimaryImage` only (product-adjacent) |
| Button | 3 | Generic |
| Routing smoke | 3 | Login page boot |

**Product management test coverage: effectively zero.**

### 7.2 Missing Tests

| Type | Suggested coverage |
|---|---|
| **Unit — slug helper** | `generateSlug(name)`, uniqueness suffix |
| **Unit — product validation** | price/discount rules, required fields |
| **Unit — image helper** | merge images, set primary, remove by url |
| **Unit — productService** | filter params (featured, category_id, is_active) |
| **Unit — adminService** | uploadImages error paths (mock Supabase) |
| **Integration — AdminProductForm** | create payload shape, edit prefill |
| **Integration — featured filter** | Home loads `featured=true` products |
| **Integration — slug routing** | ProductDetail resolves slug param |
| **Migration 012** (if any) | slug UNIQUE, category constraints |
| **E2E** (optional) | Admin create product with image → appears on Shop |

---

## 8. Step 7 — Design: Implementation Plan

### 8.1 Design Principles

1. **Canonical FK model** — `category_id` only; stop writing `category` text; plan gated drop
2. **Single image model** — `products.images` jsonb with storage `path`; deprecate `image_url` writes
3. **Slug as first-class** — auto-generate, admin-editable, UNIQUE at DB, used in all URLs
4. **Featured means featured** — filter `featured=true` on Home and optional Shop filter
5. **Minimal new migrations** — one forward migration `012_product_management.sql` for constraints/slug/column fixes
6. **No scope creep** — no SKU, no variants, no reviews, no coupons in WS2

### 8.2 Proposed Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        ADMIN UI                              │
│  AdminProducts  AdminProductForm  AdminCategories (NEW)    │
└────────────┬───────────────────────┬────────────────────────┘
             │                       │
┌────────────▼───────────┐  ┌────────▼──────────────────────┐
│    adminService.js      │  │    productService.js           │
│  CRUD, uploadImages,    │  │  getProducts (featured, slug), │
│  deleteImages,          │  │  getProduct (slug+id),         │
│  category CRUD          │  │  getCategories                 │
└────────────┬───────────┘  └────────┬────────────────────────┘
             │                       │
┌────────────▼───────────────────────▼────────────────────────┐
│                     Supabase                                   │
│  products (+slug UNIQUE)  categories  storage.products bucket  │
│  RLS: public read active products (optional 012)               │
└───────────────────────────────────────────────────────────────┘
             │
┌────────────▼───────────────────────────────────────────────┐
│                     STOREFRONT                                │
│  Home (featured=true)  Shop  ProductDetail (slug+id)  Card   │
└───────────────────────────────────────────────────────────────┘
```

### 8.3 Database Changes — Migration `012_product_management.sql` (proposed)

| Change | Risk | Breaking? |
|---|---|---|
| Add `products.updated_at` to migration chain (if not in 002) | Low | No |
| Backfill slugs from `name` where NULL; add UNIQUE on `products.slug` | Medium | No |
| Add UNIQUE on `categories.slug` | Low | No |
| Optional: `CHECK (price >= 0)`, `CHECK (discount_price IS NULL OR discount_price <= price)` | Low | No |
| Optional: RLS `products` SELECT → `is_active OR is_admin()` | Low | Hides inactive on anon |
| Seed script / migration data for initial categories | Low | No |
| **Do NOT drop** `products.category` text in WS2 — document for WS3 | — | — |

### 8.4 Frontend Changes (by priority)

#### Phase A — Fix broken flows (P0)

| Task | Files |
|---|---|
| Fix Home category links to use `cat.id` | `Home.jsx` |
| Add `featured` filter to `getProducts`; Home uses `featured: true` | `productService.js`, `Home.jsx` |
| ProductDetail uses `getProduct(idOrSlug)` not `getProductById` | `ProductDetail.jsx` |
| Fix gallery `activeImage` display | `ProductDetail.jsx` |
| Remove debug Supabase query | `Home.jsx` |
| Surface upload errors in AdminProductForm | `AdminProductForm.jsx` |

#### Phase B — Admin product completeness (P0–P1)

| Task | Files |
|---|---|
| Slug field + auto-generate from name | `AdminProductForm.jsx`, `utils/slug.js` (new) |
| Image gallery manager on edit (preview, delete, primary, merge) | `AdminProductForm.jsx`, `components/admin/ImageGallery.jsx` (new) |
| `deleteProduct` UI with confirm + storage cleanup | `AdminProducts.jsx`, `adminService.js` |
| Category admin page CRUD | `AdminCategories.jsx` (new), `App.jsx`, `AdminLayout.jsx` |
| Validation module for product form | `utils/productValidation.js` (new) |

#### Phase C — UX polish (P2)

| Task | Files |
|---|---|
| Sync Shop filters to URL (`category`, `search`, `sort`) | `Shop.jsx` |
| Admin list filters (category, status, featured) | `AdminProducts.jsx` |
| Product preview link | `AdminProducts.jsx`, `AdminProductForm.jsx` |
| Featured badge on admin list | `AdminProducts.jsx` |
| Empty states | `AdminProducts.jsx`, `AdminCategories.jsx` |
| Remove legacy `category` text fallbacks (after categories seeded) | Multiple |

#### Phase D — Storage hardening (P1)

| Task | Files |
|---|---|
| Sanitize filenames; use UUID-based paths | `adminService.uploadImages` |
| `deleteProductImages(productId, paths)` | `adminService.js` |
| Cleanup storage on product delete | `adminService.deleteProduct` |
| Client image type/size validation | `AdminProductForm.jsx` |

### 8.5 Service Changes Summary

| Service | New/updated methods |
|---|---|
| `productService` | `getProducts({ featured, slug, ... })`, unify `getProduct` for storefront |
| `adminService` | `deleteProductImages`, slug-aware create, category slug helpers |
| `utils/slug.js` | `generateSlug`, `ensureUniqueSlug` |
| `utils/productValidation.js` | `validateProductForm(payload)` |

### 8.6 Testing Plan

| Phase | Tests |
|---|---|
| A | `slug.test.js`, `productValidation.test.js`, `productService.featured.test.js` |
| B | `AdminProductForm.test.jsx` (payload, slug gen), `ImageGallery.test.jsx` |
| C | `Home.featured.test.jsx`, routing slug resolution |
| D | `adminService.upload.test.js`, migration-012 SQL contract test |
| Target | +25–30 tests; total ~75 |

### 8.7 Implementation Order

| Step | Work | Depends on |
|---|---|---|
| 1 | `utils/slug.js` + tests | — |
| 2 | Fix Home category links + featured filter | — |
| 3 | ProductDetail slug routing + gallery fix | Step 1 |
| 4 | Migration 012 (slug UNIQUE, backfill, updated_at in chain) | Step 1 |
| 5 | AdminProductForm: slug field, validation, upload errors | Steps 1, 4 |
| 6 | Image gallery component | Step 5 |
| 7 | AdminCategories page | Migration 012 or seed categories |
| 8 | Delete product + storage cleanup | Step 6 |
| 9 | Shop URL sync, admin filters, polish | Steps 2–8 |
| 10 | Tests + docs + implementation report | All |

**Estimated scope:** ~15–20 files touched, 1 new migration, 4–5 new components/utils, +25 tests.

### 8.8 Production Rollout Plan

1. **Backup** before migration 012 (same protocol as Phase 1.8)
2. **Seed categories** on live (instruments, etc.) and backfill product `category_id`
3. **Apply 012** — slug backfill + UNIQUE constraints (verify 0 duplicate slugs first)
4. **Deploy frontend** — slug URLs, featured Home, category links
5. **Smoke test:** create product with images → appears on Shop → slug URL works → featured toggle affects Home
6. **Validate** storage: upload, delete, product delete cleanup

### 8.9 Risks & Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Slug UNIQUE migration fails on duplicates | Medium | Pre-flight `SELECT slug, count(*) ... HAVING count(*) > 1`; backfill NULL slugs first |
| Breaking existing product URLs (UUID-only bookmarks) | Low | `getProduct` tries UUID first, then slug |
| Image merge bug loses existing gallery | High | Phase B gallery component with explicit merge logic + tests |
| Category delete orphans products | Medium | Confirm dialog; FK SET NULL is safe |
| Storage orphan accumulation | Medium | Cleanup on delete; optional admin "storage audit" later |
| Dropping `category` text too early | Medium | Defer to WS3; keep fallback reads until categories seeded |
| Over-scoping WS2 (reviews, variants) | Medium | Explicit non-goals; remove cosmetic ProductDetail fields or gate |

---

## 9. Step 8 — Report Sections

### 9.1 Current Implementation

- **Database:** Full product/category schema post-011 with FK, FTS, stock CHECK, storage bucket
- **Admin:** Create/edit/list products; toggle active; inventory page; category select (empty categories on live)
- **Storefront:** Shop with filters; product detail; cart integration (WS1)
- **Storage:** Upload to `products` bucket; public URLs in jsonb `images`

### 9.2 Missing Features

- Category admin UI
- Product delete UI + storage cleanup
- Slug generation and routing
- Featured merchandising on Home
- Image gallery management on edit
- Shop filter URL persistence
- Product form validation (business rules)
- Product-specific tests
- Category landing pages (optional)

### 9.3 Broken Features

- Home category links (name vs UUID)
- Slug-based product URLs
- Featured Products section (shows newest, not featured)
- ProductDetail image gallery
- Silent image upload failures
- Edit overwrites images without merge

### 9.4 Files Likely to Change

**New:**
- `frontend/src/pages/admin/AdminCategories.jsx`
- `frontend/src/components/admin/ImageGallery.jsx`
- `frontend/src/utils/slug.js`
- `frontend/src/utils/productValidation.js`
- `supabase/migrations/012_product_management.sql`
- Test files (6–8 new)

**Modified:**
- `frontend/src/pages/admin/AdminProductForm.jsx`
- `frontend/src/pages/admin/AdminProducts.jsx`
- `frontend/src/pages/Home.jsx`
- `frontend/src/pages/ProductDetail.jsx`
- `frontend/src/pages/Shop.jsx`
- `frontend/src/services/productService.js`
- `frontend/src/services/adminService.js`
- `frontend/src/components/products/ProductCard.jsx`
- `frontend/src/App.jsx`
- `frontend/src/components/layout/AdminLayout.jsx`

### 9.5 Proposed Architecture

See §8.2 — layered admin/storefront services over Supabase products/categories/storage with slug-first URLs and jsonb image gallery.

### 9.6 Database Requirements

- Migration `012`: slug UNIQUE (products + categories), backfill, optional price CHECKs, `updated_at` in chain
- Category seed data for live
- Optional RLS inactive filter
- **No SKU column**

### 9.7 UI Requirements

- AdminCategories CRUD page
- Slug field with auto-generate on AdminProductForm
- Image gallery manager (preview, primary, delete, add)
- Delete product with confirmation
- Featured filter on Home
- Fix category chips and slug product links
- Field validation feedback on admin form

### 9.8 Testing Strategy

- Unit: slug, validation, image helpers, service filters
- Integration: form submit payloads, featured Home load, slug routing
- Migration: SQL contract test for 012
- Target: +25–30 tests; no E2E required for WS2 MVP unless time permits

### 9.9 Risks

See §8.9. Highest: slug migration duplicates, image merge data loss, scope creep into variants/reviews.

### 9.10 Production Readiness Assessment

| Criterion | Current | After WS2 (target) |
|---|---|---|
| Product CRUD | Partial (no delete) | ✅ Complete |
| Categories | Service only, 0 on live | ✅ Admin UI + seeded |
| Images | Upload on create only | ✅ Full lifecycle |
| Visibility | is_active wired (WS1) | ✅ + optional RLS |
| Featured | Admin sets, storefront ignores | ✅ Home filters featured |
| Slugs | Broken routing | ✅ UNIQUE + URLs work |
| Validation | HTML5 only | ✅ Business rules |
| Admin UX | Adequate | ✅ Production-grade |
| Storage | Upload only | ✅ Delete + cleanup |
| Tests | 0 product tests | ✅ Core coverage |

**Current readiness: NOT READY** for product management as a complete system.  
**Post-WS2 target: GO** for product CRUD, categories, images, visibility, and featured merchandising.

---

## 10. Non-Goals (WS2)

- SKU / barcode / variant-level products
- Product reviews and ratings (remove cosmetic UI or defer)
- Product variations admin (cosmetic UI exists; no backend)
- Coupons, bundles, related products
- Full-text search UI (index exists; search box uses `ilike` only)
- Dropping `products.category` text column (defer WS3)
- Multi-language / i18n product fields

---

**STOP.** Audit and design complete. No code modified. No migrations created. Implementation deferred to Phase 2 Workstream 2 execution phase.
