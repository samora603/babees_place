# Release Summary — Babees Place v1.0.0-RC1

**Date:** 2026-08-04  
**npm version:** `1.0.0-rc.1`  
**Git tag (recommended):** `v1.0.0-RC1`

## Project statistics

| Metric | Value |
|--------|--------|
| Storefront pages | ~16 (`frontend/src/pages/*.jsx`) |
| Admin pages | ~18 (`frontend/src/pages/admin/*.jsx`) |
| React components | ~91 (`frontend/src/components/**/*.jsx`) |
| Active SQL migrations | 19 (`supabase/migrations/001`–`019`) |
| Public tables (live) | ~30 |
| Public RPCs (approx.) | ~25+ (orders, payments, notifications, loyalty, admin) |
| Unit/component tests | **334** (63 files) |
| Lint | **0** errors / **0** warnings |
| Production build | Pass (~25–60s) |
| JS bundle (gzip, all chunks) | ~0.37 MB total JS gzip; charts ~105 KB gz (admin-lazy); entry-ish ~130 KB gz |
| Category banner assets | 12 × 16:9 JPG |
| Hero slides | 6 |

## Accessibility

- Skip-to-content (storefront + admin)
- Labeled Login/Register; navbar search/cart/wishlist/mobile controls
- Social and icon-button `aria-label`s; focus-visible rings on key controls
- Product gallery / category images carry alt text

## Security

- Anon-only Vite env; production build fails if Supabase env missing
- Vercel headers: CSP (self + Supabase + Unsplash + Google Fonts), HSTS, Referrer-Policy, Permissions-Policy, X-Frame-Options, X-Content-Type-Options, COOP, CORP
- RLS enabled on application tables (per migrations)

## Performance

- Route-level `React.lazy` for pages; admin charts lazy
- Manual chunks: `react`, `supabase`, `charts`, `icons`
- `loading="lazy"` on product/category imagery
- CDN product images with width/quality query params

## Future work

- GA tag `v1.0.0` after production domain smoke
- Lighthouse CI + optional Playwright gate
- Own-hosted media; product sitemap
- Live Daraja go-live checklist

## Related docs

- [CHANGELOG.md](../CHANGELOG.md)
- [RELEASE_NOTES_v1.0.0-RC1.md](../RELEASE_NOTES_v1.0.0-RC1.md)
- [GITHUB_RELEASE_v1.0.0-RC1.md](../GITHUB_RELEASE_v1.0.0-RC1.md)
