# Babees Place — Release Notes · v1.0.0-RC1

**Status:** Release Candidate  
**Date:** 2026-08-04  
**Tag:** `v1.0.0-RC1`  
**Package:** `babis-place-frontend@1.0.0-rc.1`

## Summary

RC1 packages the completed database sync, checkout verification, demo catalog media, and release-hardening work (hygiene, lint, accessibility, SEO origin config, and Vercel security headers) for public candidate evaluation.

## What’s included

### Database sync
- Migrations **001–019** applied on the linked Supabase project
- Payments, notifications, promotions/loyalty, and operations (admin audit) available

### Checkout completion
- Frontend ↔ `place_order` 14-parameter contract verified
- Pickup and delivery COD paths exercised
- Inventory, order items, loyalty, and admin status flows validated

### Media overhaul
- Curated primary/gallery/thumb imagery with alt text
- Category banners and restored hero carousel assets
- Media apply script for data-only refreshes

### Performance
- Admin dashboard charts remain lazy-loaded
- Manual chunks for React, Supabase, Recharts, and icons
- Product and category images use `loading="lazy"`

### Accessibility
- Skip to content
- Labels on Login/Register; `aria-label`s on icon controls, search, cart, wishlist, socials, mobile nav
- Focus-visible rings on key interactive surfaces

## Known limitations

- Set `VITE_SITE_URL` in hosting before treating SEO/sitemap as production-final
- M-Pesa live Edge/Daraja configuration is optional for RC demos
- No referral field on checkout UI
- E2E smoke is opt-in (`npm run test:e2e`), not required in CI
- Security headers apply on Vercel; other hosts need equivalent config

## Future roadmap

1. GA (`v1.0.0`) after production domain, SEO verification, and smoke on the live URL  
2. Lighthouse CI + optional Playwright gate  
3. Own-hosted catalog media (Storage/Cloudinary)  
4. Payment provider go-live checklist  

## Upgrade / deploy notes

Required env (frontend):

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `VITE_SITE_URL` (recommended for RC/production SEO)

Vercel: Root Directory = `frontend`. Redeploy after env changes.

See also: [GITHUB_RELEASE_v1.0.0-RC1.md](./GITHUB_RELEASE_v1.0.0-RC1.md), [docs/RELEASE_SUMMARY_v1.0.0-RC1.md](./docs/RELEASE_SUMMARY_v1.0.0-RC1.md).
