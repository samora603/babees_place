# Phase 2 Workstream 5 — Milestone 5.3 Implementation Report

**Recommendations & Personalized Experiences**  
Date: 2026-07-13  
Status: Complete

---

## Objective

Improve product discovery with lightweight, deterministic, maintainable recommendations using only existing application data (plus one anonymized bestsellers RPC). No ML. No external recommendation APIs.

---

## Features delivered

| Feature | Status |
|---|---|
| Recently viewed (12, local, guests) | ✅ |
| Recommendation ranking (category / brand / price / bestsellers / new) | ✅ |
| Buy Again from order history | ✅ |
| You May Also Like (PDP) | ✅ |
| Home Discover sections | ✅ |
| Cart cross-sell | ✅ |
| Empty-state personalization | ✅ |
| Reusable carousels / skeletons | ✅ |
| Accessibility (keyboard, ARIA, focus) | ✅ |
| Unit tests | ✅ |
| Documentation | ✅ |

---

## Architecture decisions

1. **Pure ranking in `models/recommendations.js`** — services fetch; UI renders.
2. **Recently viewed = localStorage** — no login required; no PII in DB.
3. **No `brand` column** — brand weight applies only when `product.brand` exists (future-proof); category + price carry ranking today.
4. **Migration `015`** — `get_bestseller_product_ids(limit)` SECURITY DEFINER so storefront can show anonymized bestsellers without reading other users' order rows under RLS. Falls back to featured/newest if RPC missing.
5. **Lazy-loaded carousels** on Home / PDP to keep initial paint light.
6. **60s in-memory cache** on recommendation fetches to avoid duplicate pool queries.
7. **Reuse `ProductCard`** inside strips so add-to-cart / wishlist stay consistent.

---

## Files added

| File | Purpose |
|---|---|
| `supabase/migrations/015_recommendations.sql` | Bestsellers RPC |
| `frontend/src/models/recommendations.js` | Ranking / dedupe / buy-again / cross-sell |
| `frontend/src/models/recommendations.test.js` | Model tests |
| `frontend/src/services/recentlyViewedService.js` | Local view history |
| `frontend/src/services/recentlyViewedService.test.js` | Service tests |
| `frontend/src/services/recommendationService.js` | Orchestration + cache |
| `frontend/src/services/recommendationService.test.js` | Service tests |
| `frontend/src/services/buyAgainService.js` | Order-frequency buy again |
| `frontend/src/services/buyAgainService.test.js` | Buy-again tests |
| `frontend/src/test/migration-015.test.js` | Migration contract tests |
| `frontend/src/components/recommendations/*` | UI primitives + sections |
| `docs/audits/Phase2_WS5_Milestone5.3_Report.md` | This report |

### Components under `components/recommendations/`

- `SectionHeader.jsx`
- `RecommendationSkeleton.jsx`
- `ProductRecommendationCard.jsx`
- `ProductStrip.jsx`
- `RecommendationCarousel.jsx`
- `RecentlyViewedCarousel.jsx`
- `YouMayAlsoLike.jsx`
- `CartCrossSell.jsx`
- `ExploreSuggestions.jsx`
- `HomeDiscoverSections.jsx`

---

## Files modified

| File | Change |
|---|---|
| `frontend/src/pages/Home.jsx` | Lazy HomeDiscoverSections |
| `frontend/src/pages/ProductDetail.jsx` | trackView + You May Also Like + Recently Viewed |
| `frontend/src/pages/Cart.jsx` | Cross-sell + empty ExploreSuggestions |
| `frontend/src/pages/Wishlist.jsx` | Empty-state suggestions |
| `frontend/src/pages/Orders.jsx` | Empty-state suggestions |
| `docs/technical/06_Frontend.md` | §8 Recommendations |
| `docs/database/Migration_History.md` | Record `015` |

---

## Database changes

**Migration `015_recommendations.sql`**

- Function: `public.get_bestseller_product_ids(p_limit integer)`
- `SECURITY DEFINER`, `search_path = public`
- Returns `(product_id, units_sold)` for non-cancelled orders + active products
- `GRANT EXECUTE` to `anon`, `authenticated`

**Manual step:** apply migration `015` on the linked Supabase project before relying on true bestsellers (app falls back to featured/newest until then).

---

## Tests added

- `models/recommendations.test.js` — scoring, ranking, dedupe, cross-sell, buy-again frequency
- `recentlyViewedService.test.js` — persistence, cap, dedupe
- `recommendationService.test.js` — seed exclusion, cart exclusion, RPC fallback
- `buyAgainService.test.js` — frequency + hide OOS
- `migration-015.test.js` — SQL contract

---

## Known limitations

1. Brand affinity inactive until a `brand` column (or equivalent) exists on products.
2. Bestsellers RPC must be applied for accurate trending; fallback is featured/newest.
3. Recently viewed stores a lightweight snapshot (may show stale stock until re-open PDP).
4. Buy Again fetches products sequentially by frequency (capped); fine for typical order volumes.
5. No collaborative filtering / ML — by design.

---

## Manual testing checklist

1. Browse several products as guest → Home shows Recently Viewed.
2. Open PDP → You May Also Like excludes current product; Recently Viewed excludes current.
3. Sign in with prior orders → Buy Again on Home (only in-stock items).
4. Add items to cart → Cart shows complementary strip without cart duplicates.
5. Empty cart / wishlist / orders → explore suggestions appear.
6. Keyboard: focus product strip, use Arrow Left/Right; check focus rings on chevrons.
7. After applying `015`, confirm Trending reflects real sales volume.

---

## Stop line

Milestone 5.3 complete. **Do not begin Milestone 5.4.**
