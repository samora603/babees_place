# Babees Place

![Status](https://img.shields.io/badge/Status-v1.0.0--RC1-orange)
![Frontend](https://img.shields.io/badge/Frontend-React%20%2B%20Vite-61DAFB)
![Backend](https://img.shields.io/badge/Backend-Supabase-3ECF8E)
![Database](https://img.shields.io/badge/Database-PostgreSQL-4169E1)
![License](https://img.shields.io/badge/License-MIT-green)

**Version:** [v1.0.0-RC1](./RELEASE_NOTES_v1.0.0-RC1.md) (`frontend@1.0.0-rc.1`)

Campus-focused ecommerce storefront and admin console: catalog browsing, cart/checkout (COD + M-Pesa path), orders, rewards, and operations — backed by Supabase (Auth, Postgres, RLS, Storage).

---

## Overview

Babees Place is a Kenya-oriented ecommerce application with:

- A customer storefront (shop, wishlist, checkout, orders, rewards, notifications)
- An admin console (catalog, inventory, orders, promotions, loyalty, analytics, health)
- A PostgreSQL schema delivered as numbered Supabase migrations **001–019**
- Demo seed + curated media tooling for portfolio and QA walkthroughs

This repository is at **Release Candidate 1** — feature-complete for candidate evaluation, not yet General Availability.

---

## Features

### Customer

- Auth (email/password), profile, addresses, preferences
- Catalog browse, search, categories, featured / recommendations
- Cart, wishlist, checkout (pickup & delivery), COD + M-Pesa payment UX
- Orders, confirmation, payment status pages
- Rewards / loyalty / gift-card UI surfaces
- In-app notifications

### Admin

- Dashboard KPIs and charts
- Products, categories, inventory, pickup locations
- Orders and payment status updates
- Promotions, coupons, gift cards, loyalty rules
- Users, notifications, health, settings

### Platform

- Supabase Auth + RLS
- Security headers on Vercel
- Absolute SEO via `VITE_SITE_URL`
- CI: lint → test → build

---

## Architecture

```text
Browser (React SPA)
    │  VITE_SUPABASE_URL + anon key
    ▼
Supabase
  ├── Auth
  ├── PostgREST (tables + RPCs)
  ├── Storage (product uploads)
  └── (optional) Edge Functions — M-Pesa / email / SMS
```

- Storefront and admin share one SPA (`frontend/`), separated by route guards.
- Business rules for checkout/inventory live primarily in Postgres RPCs (`place_order`, payment helpers, loyalty, etc.).
- Migrations are the source of truth under `supabase/migrations/`.

See also: `docs/01_ARCHITECTURE.md`, `docs/architecture/`.

---

## Tech Stack

| Layer | Stack |
|--------|--------|
| Frontend | React 18, Vite 5, Tailwind CSS, React Router, Recharts, Swiper |
| Backend | Supabase (PostgreSQL 17, Auth, Storage, RLS) |
| Quality | ESLint, Prettier, Vitest, Playwright (opt-in), GitHub Actions |
| Hosting | Vercel-oriented (`frontend/vercel.json`) |

---

## Installation

```bash
git clone git@github.com:samora603/babees_place.git
cd babees_place/frontend
npm ci
cp .env.example .env   # then fill values
npm run dev
```

Quality commands (from `frontend/`):

```bash
npm run lint
npm test
npm run build
npm run test:e2e   # optional; requires Playwright browsers
```

Demo catalog seed (service role; never commit the key):

```bash
export SUPABASE_URL="https://<project-ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
npm run seed:demo
# media-only refresh:
node ../scripts/seed-demo/apply-media.mjs
```

---

## Environment Variables

| Name | Required | Purpose |
|------|----------|---------|
| `VITE_SUPABASE_URL` | Yes (prod build) | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Yes (prod build) | Public anon key only |
| `VITE_SITE_URL` | Recommended | Absolute canonical / OG / sitemap / robots origin (no trailing slash) |
| `VITE_PAYMENT_PROVIDER` | No | `mock` (default) or `daraja` |
| `VITE_ENABLE_SW` | No | Service worker registration |

Server-only secrets (`SUPABASE_SERVICE_ROLE_KEY`, Daraja keys, etc.) must **never** be placed in `VITE_*` or committed. See `frontend/.env.example`.

Vercel: Root Directory = `frontend`; set the same `VITE_*` names for Production.

---

## Demo Accounts

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@babeesplace.com` | `Admin123!` |
| Customer | `customer@babeesplace.com` | `Customer123!` |
| Other demo customers | `*@babeesplace.demo` | `DemoUser123!` |

Accounts are created by the demo seed script when applied to a project.

---

## Screenshots

Add storefront and admin captures under `docs/screenshots/` and link them here for portfolio demos:

| Surface | Suggested file |
|---------|----------------|
| Home hero | `docs/screenshots/home-hero.png` |
| Shop grid | `docs/screenshots/shop.png` |
| Checkout | `docs/screenshots/checkout.png` |
| Admin dashboard | `docs/screenshots/admin-dashboard.png` |

*(RC1 ships without committed screenshot binaries; drop-in assets are welcome before GA.)*

---

## Deployment

1. Apply Supabase migrations **001–019** (`supabase db push --linked`).
2. Configure Production env: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_SITE_URL`.
3. Deploy `frontend/` to Vercel (SPA rewrite + security headers in `vercel.json`).
4. Smoke: Home → Shop → PDP → Login → Checkout COD → Admin orders.
5. Optional: `npm run seed:demo` + `apply-media.mjs` for demo content.

Details: `RELEASE_NOTES_v1.0.0-RC1.md`, `docs/operations/`.

---

## Roadmap

**RC1 → GA (`v1.0.0`)**

- Production domain + SEO verification
- Live payment provider decision (mock vs Daraja)
- Lighthouse / optional Playwright CI gate
- Own-hosted catalog media (Storage/Cloudinary)

**Later**

- Richer product sitemap
- Mobile app / deeper loyalty programs
- Multi-vendor (out of current scope)

---

## Known Limitations

- Live M-Pesa defaults to **mock** unless Edge/Daraja is configured
- Checkout UI does not collect a **referral code** (signup/post-pay path)
- COD does not create `payments` rows (by design)
- Playwright smoke is **opt-in**, not a CI gate
- Brand spelling varies (`Babees` docs vs `Babis` in some UI strings)
- No product-level sitemap entries yet

---

## Project Layout

```text
babees_place/
├── frontend/           # React + Vite SPA
├── supabase/           # migrations + config
├── scripts/seed-demo/  # demo users, catalog, media apply
├── docs/               # engineering docs & audits
├── CHANGELOG.md
├── RELEASE_NOTES_v1.0.0-RC1.md
└── README.md
```

---

## Documentation

- Vision & plan: `docs/00_PROJECT_VISION.md`, `docs/PROJECT_MASTER_PLAN.md`
- Architecture: `docs/01_ARCHITECTURE.md`
- Security: `docs/03_Security.md`
- Engineering: `docs/ENGINEERING.md`, `docs/13_CODING_STANDARDS.md`
- Audits: `docs/audits/`
- Release summary: `docs/RELEASE_SUMMARY_v1.0.0-RC1.md`

---

## License

MIT — see [LICENSE](./LICENSE).

---

## Author

**Edwin Samora** — [github.com/samora603](https://github.com/samora603)
