# Phase 0 — Technical Debt Register

Auditor: Principal Engineer
Date: 2026-07-12
Legend — Severity: Critical / High / Medium / Low · Effort: S (≤½ day) / M (1–2 d) / L (3–5 d) · Status: OPEN / RESOLVED / DOCUMENTED.

---

| ID | Description | Severity | Impact | Effort | Status | Recommendation |
|---|---|---|---|---|---|---|
| TD-1 | `profiles_update_own` RLS lacks `WITH CHECK` → user can self-escalate to `admin` | Critical | Total authorization bypass | M | OPEN | Restrict role column / add `WITH CHECK`; role changes only via admin RPC |
| TD-2 | Client-side order fallback + permissive RLS → client-controlled `total_amount`/`price` | High | Financial integrity | M | OPEN | Remove `createOrderFromCart`; server-only totals via `place_order`; deny direct order/item inserts |
| TD-3 | DB schema not reproducible (`products` + 5 tables missing; empty `remote_schema.sql`) | High | Cannot rebuild env; RLS unverifiable | L | OPEN | `supabase db pull` baseline; remove empty migration (do not fabricate) |
| TD-4 | No indexes on FK/search columns | High | Query performance at scale | M | OPEN | Index FKs + `products(category,slug)`; add full-text search |
| TD-5 | Root `.gitignore` was a directory | High | No ignore rules; secret/artifact risk | S | **RESOLVED** | Replaced with real file (Phase 0) |
| TD-6 | `frontend/.env` committed | High (practice) | Bad-practice; future secret leak | S | **RESOLVED** | Untracked + ignored; `.env.example` added (Phase 0) |
| TD-7 | Site-wide layout bug (navbar/footer only on `/`); duplicate `/` route | High | Broken navigation everywhere | M | OPEN | Shared `<Layout>` with `<Outlet/>`; remove dead route |
| TD-8 | ESLint config missing → `npm run lint` fails (and lints `dist/`) | Medium | No quality gate | S | OPEN | Add ESLint config + `.eslintignore`; wire to CI |
| TD-9 | Broken `services/authService.js` (Markdown fences in `.js`) | Medium | Dead/invalid code | S | DOCUMENTED | Delete (unused) or rewrite when OTP is built |
| TD-10 | Dead files: `api.js`, `lib/auth.js`, `hooks/useAuth|useCart|useWishlist`, `ProductsPage.jsx`, `OtpInput.jsx` | Medium | Confusion, rot, drift | S | DOCUMENTED | Remove after confirming no planned use |
| TD-11 | Missing `/placeholder.png` (referenced fallback) | Medium | Broken images | S | OPEN | Add asset or change fallback |
| TD-12 | `adminService.uploadImages` mis-destructures `getPublicUrl` | Medium | Undefined image URLs | S | OPEN | Use `{ data: { publicUrl } }` |
| TD-13 | Services swallow errors (`error:null`); no Error Boundary; no env validation | Medium | Failures look like empty states | M | OPEN | Propagate errors; add boundary + env guard |
| TD-14 | Duplicate cart logic (`CartContext` vs unused `useCart` hook), inconsistent pricing | Medium | Divergent behavior risk | S | OPEN | Consolidate to `CartContext`; delete hook |
| TD-15 | Categories: `products.category` text vs `categories` table CRUD (contradiction) | Medium | Integrity/renaming issues | M | OPEN | Pick one model; migrate if keeping table |
| TD-16 | Mixed identifier casing (`"discountPrice"`) | Medium | Fragile SQL identifiers | M | OPEN | Standardize snake_case (`discount_price`) |
| TD-17 | No status/payment CHECK constraints; no `updated_at` trigger | Low/Med | Invalid states, stale timestamps | S | OPEN | Add CHECKs/enum + trigger |
| TD-18 | `place_order` lacks `FOR UPDATE` locking | Medium | Oversell under concurrency | S | OPEN | Lock product rows during checkout |
| TD-19 | Unused deps: `react-image-gallery`, `axios` | Low | Bundle/attack surface | S | DOCUMENTED | Remove with dead-code cleanup |
| TD-20 | 28 `console.*`; no logger | Low | Log noise / info leak | S | OPEN | Remove/replace with logger |
| TD-21 | Weak auth config (min len 6, no email confirm, no captcha) | Medium | Account security | S | OPEN | Harden `config.toml` |
| TD-22 | `config.toml` `site_url`/redirects/`project_id` wrong; `seed.sql` missing | Medium | Auth redirects break; reset fails | S | OPEN | Correct config; add/disable seed |
| TD-23 | No tests / no framework | High | No regression safety | L | OPEN | Vitest + RTL + Playwright + policy tests |
| TD-24 | Brand naming "Babees" vs "Babis" | Low | Inconsistency | S | DOCUMENTED | Pick canonical brand; align code+docs |
| TD-25 | Tooling committed in app tree (`frontend/.agents/`, `.qodo/`) | Low | Repo bloat | S | DOCUMENTED | Relocate/ignore |
| TD-26 | Empty `docs/` dirs (`operations/prompts/references/testing`) | Low | Clutter | S | DOCUMENTED | Populate, `.gitkeep`, or remove |
| TD-27 | Inconsistent service return shapes | Medium | Harder maintenance | M | OPEN | Define one service contract |
| TD-28 | No CI/CD, monitoring, logging, backups | High | Ops blind spots | L | OPEN | Add pipeline + observability |

## Summary by severity
- **Critical (1):** TD-1.
- **High (8):** TD-2, TD-3, TD-4, TD-5*, TD-6*, TD-7, TD-23, TD-28. (*resolved in Phase 0)
- **Medium (13):** TD-8, TD-9, TD-10, TD-11, TD-12, TD-13, TD-14, TD-15, TD-16, TD-18, TD-21, TD-22, TD-27.
- **Low (6):** TD-17(–), TD-19, TD-20, TD-24, TD-25, TD-26.

Resolved in Phase 0: **TD-5, TD-6** (plus documentation debt from empty docs). Everything else is tracked for Phase 1+ with the recommendations above.
