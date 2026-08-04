# Babees Place — Demo Dataset Seed

Reusable portfolio demo data for client and recruiter walkthroughs.

## What it seeds

| Data | Count | Notes |
|------|-------|--------|
| Categories | 5 | Fashion, Electronics, Home & Living, Toys & Kids, Beauty & Accessories |
| Products | 50 | KES pricing, stock 5–120, **8 featured** |
| Pickup locations | 3 | Westlands, CBD, Rongai |
| Admin | 1 | `admin@babeesplace.com` |
| Customers | 8 | Kenyan demo names (`*.@babeesplace.demo` + primary customer) |
| Addresses / preferences | per customer | Nairobi-area |
| Wishlists | ~18 lines | Across customers |
| Orders | 20 | Mixed statuses + order_items + events |
| Sample cart | 2 lines | Primary customer |
| Promotions / coupons | 4 + 4 | **Only if migration 018 is applied** |

## Schema adaptations

- **No `reviews` table** and no product rating columns → reviews are not inserted.
- **No `sku` column** → product `slug` is the stable code (`bp-fsh-001`, …).
- **Compare price** → `discount_price` when on sale.
- **Images** → curated Unsplash CDN galleries via `media-map.mjs` (primary + gallery + thumb + alt). Apply with `node scripts/seed-demo/apply-media.mjs`.
- Category banners live under `frontend/public/category_banners/{slug}.jpg` (16:9).
- Legacy non-demo products are set `is_active = false` so the storefront shows the curated 50.

## Prerequisites

1. Linked Supabase project with migrations **001–015** (minimum).
2. For promotions/coupons: apply **016–019** first, then re-run seed.
3. Service role key (never commit it).

## Run

From `frontend/` (uses local `@supabase/supabase-js`):

```bash
export SUPABASE_URL="https://<project-ref>.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"
npm run seed:demo
```

Or from repo root:

```bash
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed-demo/index.mjs
```

(Requires `@supabase/supabase-js` resolvable — run via `frontend` script preferred.)

### Media-only refresh (no reseed)

```bash
SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed-demo/apply-media.mjs
```

Updates `products.image_url` + `products.images` from `media-map.mjs` only.

## Demo logins

| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@babeesplace.com` | `Admin123!` |
| Customer | `customer@babeesplace.com` | `Customer123!` |
| Other customers | `*@babeesplace.demo` | `DemoUser123!` |

## Idempotency

- Categories, products, pickups, addresses, promotions use stable UUIDs (upsert).
- Orders tagged `note = demo-seed-v1` are deleted and recreated on each run.
