# Performance Audit — Babees Place

Auditor role: Performance Engineer
Date: 2026-07-12
Evidence: production build output (`npm run build`, verified) + static review. No runtime profiling (Lighthouse/APM) was performed — flagged where relevant as **NOT MEASURED**.

---

## Summary score: 6 / 10

Good bones: route-level code splitting works, heavy libraries (recharts) are isolated to lazy admin chunks, money/date helpers are cheap, cart totals are memoized. Main opportunities: vendor chunk splitting, an inefficient categories query, coarse realtime re-fetching, no caching layer, and unoptimized images.

---

## 1. Bundle size (measured, gzip in parentheses)

| Chunk | Raw | Gzip |
|---|---|---|
| `index-*.js` (entry: React, Router, Supabase, contexts) | 392.3 kB | 114.1 kB |
| `AdminDashboard-*.js` (recharts) | 387.4 kB | 107.2 kB |
| `Home-*.js` (swiper carousel) | 106.4 kB | 33.4 kB |
| `index-*.css` | 48.4 kB | 7.9 kB |
| All other route chunks | < 7 kB each | < 2.3 kB each |

Observations:
- ✅ **Code splitting works** — 30+ per-route chunks; admin/recharts and swiper are not in the initial load for regular shoppers.
- ⚠️ **Entry chunk 392 kB (114 kB gz)** bundles React + Router + supabase-js together. Add `build.rollupOptions.output.manualChunks` to split a stable `vendor` chunk (better long-term caching) and separate `supabase`.
- ⚠️ **`AdminDashboard` 387 kB** is dominated by `recharts`. It's lazy (good) but consider a lighter chart lib or dynamic-importing charts within the page.
- ⚠️ **Home 106 kB** — `swiper` is heavy for a single hero carousel; a CSS scroll-snap carousel would remove the dependency.

## 2. Data fetching / queries
- ❌ **`productService.getCategories`** (`productService.js:60-74`) selects **every product row** just to derive a unique category list on the client. This is an unbounded full-table scan run whenever categories are needed. Replace with a real `categories` table or a Postgres `DISTINCT`/RPC.
- ⚠️ **`ilike '%term%'` search** (`getProducts`) cannot use a b-tree index → full scan per search. Move to full-text search (`tsvector`+GIN) — see DATABASE_AUDIT.
- ⚠️ **No FK indexes** (see DATABASE_AUDIT §3.1): order/cart joins and ownership filters seq-scan as data grows.
- ✅ Pagination uses `range()` with `count: 'exact'` — server-side, good. (`count: 'exact'` adds a count query cost; `estimated` is cheaper at scale.)
- ✅ `adminService.getStats` parallelizes counts with `Promise.all` and `head: true` count queries. Good. (Revenue is computed client-side over all orders — will not scale; move to a SQL aggregate/RPC.)

## 3. React rendering / re-renders
- ✅ `CartContext` memoizes `itemCount`/`subtotal` with `useMemo`; callbacks use `useCallback`.
- ⚠️ Context value objects are recreated each render (not wrapped in `useMemo`), so all consumers re-render on any context change. For `AuthContext`/`WishlistContext` this is minor but worth memoizing the `value`.
- ⚠️ **Realtime over-fetching:** `useCart` and `WishlistContext` subscribe to **all** changes on `cart`/`wishlist` and re-fetch the entire collection on every event (`useCart.js:36`, `WishlistContext.jsx:23`). Filter the subscription to the current user and/or apply the payload delta instead of full refetch.
- NOT MEASURED: actual render counts / wasted renders (needs React Profiler).

## 4. Caching / network
- ❌ **No client cache** (no React Query/SWR). Every page mount re-issues queries; navigating back re-fetches. Introducing TanStack Query would cut redundant network calls and give stale-while-revalidate.
- ❌ No HTTP cache headers strategy documented for static assets/CDN.
- ⚠️ Duplicate cart fetch paths (`CartContext` + unused `useCart`) risk double queries if both were ever mounted.

## 5. Images
- Hero images are JPEG/JPEG in `public/hero_carousel/` and `public/assets/images/` served as-is: **no responsive `srcset`, no width/height, no `loading="lazy"`, no modern format (WebP/AVIF)**.
- Supabase image transformation is available (Pro) but disabled in `config.toml`.
- Missing `/placeholder.png` causes failed image requests (see FRONTEND_AUDIT §7).
- NOT MEASURED: LCP/CLS — hero carousel + missing dimensions likely hurt CLS.

## 6. Database performance
Cross-reference DATABASE_AUDIT: no indexes, `ilike` search, client-side revenue aggregation, `getCategories` full scan. These are the highest-ROI performance fixes.

## 7. Prioritized optimizations
1. Add DB indexes (FKs + `products.category`/`slug`) and full-text search. *(Biggest real-world win.)*
2. Replace `getCategories` full scan and client-side revenue aggregation with SQL/RPC.
3. Add `manualChunks` vendor splitting; evaluate dropping `swiper`/`recharts` weight.
4. Add a client query cache (TanStack Query).
5. Scope realtime subscriptions to the user; avoid full re-fetch on each event.
6. Optimize images (WebP, `srcset`, explicit dimensions, `loading="lazy"`; enable Supabase image transforms if on Pro).
7. Memoize context `value` objects.
8. Run Lighthouse + React Profiler to get baseline Core Web Vitals (currently NOT MEASURED).
