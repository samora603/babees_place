# Babees Place v1.0.0-RC1

Release Candidate for the Babees Place ecommerce platform.

## Highlights

- Database synchronized through migrations **001–019**
- Checkout verified (pickup + delivery COD; 14-arg `place_order`)
- Curated demo catalog media + category banners
- Accessibility pass (skip link, labels, icon `aria-label`s, focus rings)
- Absolute SEO via `VITE_SITE_URL` + build-time sitemap/robots
- Vercel security headers (CSP, HSTS, and related)
- **334** tests passing · ESLint **0/0** · production build green

## Breaking Changes

None for existing demo clients on migrations 001–019.

> Hosts must set `VITE_SITE_URL` for absolute OG/canonical/sitemap output. Without it, SEO falls back to relative/runtime origin behavior.

## Database

- Applied: `001` … `019` (payments, notifications, promotions/loyalty, operations)
- Critical RPC: `place_order` (14 parameters) aligned with frontend
- Fix included: complete `::integer` cast in `award_loyalty_for_order` (018)

## Features

- Storefront: shop, PDP galleries, cart, checkout rewards fields, orders, rewards
- Admin: catalog, orders, promotions, coupons, gift cards, loyalty, analytics
- Demo seed (`scripts/seed-demo`) + `apply-media.mjs`
- CI lint/test/build; Vercel SPA rewrites + headers

## Bug Fixes

- Incomplete loyalty points cast in migration 018 SQL
- Missing hero carousel assets (slides 5–6)
- Broken relative `placeholders/*` product image paths
- ESLint warnings cleared (unused imports, Checkout hook deps)
- Footer social `href="#"` placeholders replaced with labeled links

## Known Issues

- M-Pesa live provider optional (mock default)
- No referral field on checkout UI
- COD creates no `payments` row (by design)
- Playwright e2e not gated in CI
- Product-level sitemap URLs not generated
- Some UI strings still use “Babis” spelling

## Upgrade Notes

1. Ensure remote DB is on **001–019** (`supabase db push --linked`).
2. Set frontend env:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_SITE_URL` (production origin, no trailing slash)
3. Deploy with Root Directory = `frontend`.
4. Optional demo refresh: `npm run seed:demo` then `node scripts/seed-demo/apply-media.mjs`.
5. Smoke Home → Shop → Checkout COD → Admin orders.

**Package version:** `1.0.0-rc.1`  
**Recommended next tag after GA criteria:** `v1.0.0`
