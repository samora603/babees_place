# Changelog

All notable changes to Babees Place are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/). Version tags use **v1.0.0-RC1** style; npm uses SemVer `1.0.0-rc.1`.

Historical Phase 0 notes remain in `docs/CHANGELOG.md`.

## [v1.0.0-RC1] — 2026-08-04

### Added
- Configurable `VITE_SITE_URL` for absolute canonical, Open Graph, Twitter, JSON-LD, sitemap, and robots URLs
- Production security headers on Vercel (`CSP`, `HSTS`, `Referrer-Policy`, `Permissions-Policy`, `X-Frame-Options`, `X-Content-Type-Options`, `COOP`, `CORP`)
- Skip-to-content link and broader storefront/admin accessibility labels and focus-visible rings
- Curated product media map + category banners (Sprint 3)
- Demo seed tooling under `scripts/seed-demo/`
- MIT `LICENSE`, RC1 release notes and summary docs

### Changed
- Homepage categories use 16:9 banner cards
- SEO head runtime updater uses site origin helpers
- Package version set to `1.0.0-rc.1` (tag **v1.0.0-RC1**)
- Root README rewritten for RC1 install, env, demo accounts, deployment, limitations

### Fixed
- ESLint warnings cleared (unused imports/vars, Checkout rewards hook dependencies)
- Missing hero carousel slides 5–6 restored
- Broken relative product placeholder paths replaced with CDN galleries
- Incomplete `::integer` cast in `award_loyalty_for_order` (migration 018)

### Database (Sprints 1–2)
- Remote schema synchronized through migrations **001–019**
- Checkout verified against 14-parameter `place_order` RPC

### Known limitations
- Live M-Pesa Daraja is optional (mock provider by default)
- Referral code is not collected on the checkout form (signup/post-pay path)
- COD does not create `payments` rows by design
- Product sitemap lists storefront entry points only (not every SKU URL)
- Playwright smoke exists but is not a CI gate

### Future roadmap
- Production domain cutover + absolute SEO verification
- Lighthouse CI budgets
- Optional E2E gate in CI
- Cloudinary / Supabase Storage ownership of catalog media
