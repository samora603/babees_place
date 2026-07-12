# Babees Place — Complete Engineering Audit

Auditor: Principal Engineer / Architect / Security / DevOps / QA / Tech Writer / Reviewer
Date: 2026-07-12
Method: Evidence-based static review of the full repository. The build was compiled successfully; lint was executed (and fails); the **live Supabase project was not accessed** — remote-only facts are marked **UNVERIFIED**.

Companion documents:
- `docs/audits/SECURITY_AUDIT.md`
- `docs/audits/FRONTEND_AUDIT.md`
- `docs/audits/DATABASE_AUDIT.md`
- `docs/audits/SUPABASE_AUDIT.md`
- `docs/audits/PERFORMANCE_AUDIT.md`
- `docs/audits/PRODUCTION_READINESS.md`
- `docs/NEXT_STEPS.md` (sprint roadmap)

> **Environment note:** the workspace is configured as `Babees_Place` but the actual directory is `babees_place` (lowercase). This case mismatch breaks some path-based tooling and should be reconciled.

---

## PART 1 — Documentation Audit

### Inventory (19 doc files)
**Populated (10):** `README.md`, `docs/00_PROJECT_VISION.md`, `docs/01_ARCHITECTURE.md`, `docs/13_CODING_STANDARDS.md`, `docs/AI_COLLABORATION.md`, `docs/AUTOMATIONS.md`, `docs/CHANGELOG.md`, `docs/DECISIONS.md`, `docs/ENGINEERING.md`, `docs/PROJECT_MASTER_PLAN.md`.

**Empty — 0 bytes (9):** `docs/03_Security.md`, `docs/10_Final_Checklist.md`, `docs/audits/01_Project_Audit.md`, `docs/technical/02_Database.md`, `docs/technical/04_Authentication.md`, `docs/technical/05_API.md`, `docs/technical/06_Frontend.md`, `docs/technical/07_Admin.md`, `docs/technical/08_Deployment.md`, `docs/technical/09_Testing.md`.

### Findings
- **Half the documentation set is empty.** All of `docs/technical/*` (Database, Authentication, API, Frontend, Admin, Deployment, Testing) plus Security and the Final Checklist are placeholders. The most implementation-critical docs do not exist.
- **Corrupt filename:** `docs/technical/04_Authentication.md` contains a literal newline in its filename (`04_Authentication.md\n`), confirmed via `ls | cat -A` and a failing `wc`. This is a filesystem defect.
- **Contradiction — CHANGELOG vs reality:** `CHANGELOG.md` lists `v0.2.0 Authentication completed`, `v0.5.0 Orders`, `v1.0.0 Production Release`, implying the product shipped. `PROJECT_MASTER_PLAN.md` marks Deployment/Testing "Not Started" and most modules "In Progress". Git has **exactly 1 commit**. The changelog is aspirational, not factual.
- **Broken references:** `README.md` and `DECISIONS.md` (ADR-014) describe `scripts/` and `.github/` folders that **do not exist**. `AI_COLLABORATION.md` tells contributors to read `ARCHITECTURE.md`, `CODING_STANDARDS.md`, `AUTOMATIONS.md` — file names don't match (`01_ARCHITECTURE.md`, `13_CODING_STANDARDS.md`) and no path is given.
- **Brand inconsistency:** docs say "**Babees** Place"; code says "**Babis** Place" (`package.json` name `babis-place-frontend`, migration header, `Login.jsx` heading "Babis Place"). Pick one.
- **Inconsistent numbering:** files jump 00, 01, 03, 10, 13 with gaps, mixed with unnumbered docs (`ENGINEERING`, `DECISIONS`, …). No index/table of contents.
- **Duplication of principles:** security/RLS/DoD rules are repeated near-verbatim across `ENGINEERING.md`, `AI_COLLABORATION.md`, `13_CODING_STANDARDS.md`, `AUTOMATIONS.md`, `DECISIONS.md`. High redundancy, high drift risk.

### Recommendations
- **Fill the empty technical docs** (or delete the stubs until written) — prioritize Database schema, Authentication, API/services, Deployment, Testing.
- Fix the `04_Authentication.md\n` filename.
- Rewrite `CHANGELOG.md` to reflect actual state (pre-1.0, single commit).
- Remove `scripts/`/`.github/` references until those exist (or create them).
- Consolidate the repeated "principles/DoD/security" prose into **one** canonical `ENGINEERING.md` and have others link to it.
- Add a `docs/README.md` index; standardize naming (either number everything or nothing).
- Add missing artifacts: architecture diagram (C4/sequence), ERD, onboarding/setup guide, deployment runbook, ADRs for the actual data model.

---

## PART 2 — Project Structure Audit

```
babees_place/
├── docs/            (see Part 1)
├── frontend/        React app (src well-organized)
├── supabase/        migrations + config
├── README.md
└── .gitignore/      ❌ a DIRECTORY, not a file
```

### Findings
- ❌ **Root `.gitignore` is an empty directory** → no repo-level ignore rules (HIGH — SECURITY_AUDIT C-3).
- ❌ **`frontend/.env` is committed**; no `.env.example`; `frontend/` has no `.gitignore` (SECURITY_AUDIT C-2).
- ✅ `frontend/src` is cleanly organized: `components/{ui,layout,products,orders,auth}`, `pages/{,admin}`, `context`, `hooks`, `services`, `lib`, `utils`. Matches the documented structure.
- ⚠️ **`frontend/.agents/skills/**`** (supabase skill docs, ~40 files) is committed inside the app — vendor/tooling material that bloats the app tree; move out or ignore.
- ⚠️ **Duplicate/legacy Supabase client files:** `lib/supabase.js` (re-export) + `lib/supabaseClient.js` (real client). Services import inconsistently from both. Consolidate to one path.
- ❌ **Dead files** (unused, confirmed by import search): `services/api.js`, `services/authService.js` (also *broken* — Markdown fences in `.js`), `lib/auth.js`, `hooks/useAuth.js`, `hooks/useCart.js`, `hooks/useWishlist.js`, `pages/ProductsPage.jsx`, `components/auth/OtpInput.jsx`.
- ❌ Missing folders referenced by docs: `scripts/`, `.github/`.
- ⚠️ `supabase/.temp/` (linked project ref etc.) is git-ignored via `supabase/.gitignore` (good), but `supabase/migrations/20260617042152_remote_schema.sql` is an empty tracked file.

### What to do
- **Delete:** dead files listed above; empty `remote_schema.sql`.
- **Move/ignore:** `frontend/.agents/` out of the app.
- **Fix:** root `.gitignore` (make it a real file), untrack `.env`, add `.env.example`.
- **Create:** `.github/workflows/` (CI), optional `scripts/` (or drop the references).
- **Keep:** the `src/` layout, `supabase/config.toml`, migration `001`.

---

## PART 3 — Frontend Audit
Full detail in `FRONTEND_AUDIT.md`. Headlines: clean layered architecture and good code-splitting; **site-wide layout bug** (navbar/footer only on `/`), duplicate `/` route, error-swallowing services, no Error Boundary, dead/broken files, missing `/placeholder.png`, storage `getPublicUrl` bug, broken lint, zero tests. **Score 6/10.**

## PART 4 — Supabase Audit
Full detail in `SUPABASE_AUDIT.md`. Headlines: only 4 of ~11 tables in migrations; empty remote-schema migration; solid `place_order` RPC + `is_admin()`; **`profiles` role-escalation RLS flaw**; storage/realtime unverified; wrong redirect URLs. **Score 5/10.**

## PART 5 — Security Audit
Full detail in `SECURITY_AUDIT.md`. **Security score 4/10.** Critical: privilege escalation via `profiles` update; committed `.env`; broken root ignore. High: client-controlled order totals; unreproducible schema/unverified RLS.

## PART 6 — Database Audit
Full detail in `DATABASE_AUDIT.md`. Solid core normalization; **no indexes**; irreproducible schema; unnormalized categories; mixed identifier casing; no status CHECK constraints. **Score 5/10.**

## PART 7 — Performance Audit
Full detail in `PERFORMANCE_AUDIT.md`. Code-splitting works; entry ~392 kB / AdminDashboard ~387 kB (recharts, lazy); `getCategories` full-table scan; coarse realtime refetch; no client cache; unoptimized images. **Score 6/10.**

## PART 8 — Testing Audit
Full detail in `PRODUCTION_READINESS.md`. **0% coverage**, no framework, lint broken. **Score 1/10.**

## PART 9 — Deployment Audit
Full detail in `PRODUCTION_READINESS.md`. Build works; everything else (CI, monitoring, logging, backups, secrets, migrations, payments) missing or broken. **Not production ready — 3/10.**

---

## PART 10 — Feature Completeness (vs PROJECT_MASTER_PLAN)

Evidence-based estimates from routed pages, services, and migrations. (Remote data/behavior UNVERIFIED where noted.)

| Feature | % | Evidence / gaps |
|---|---:|---|
| Authentication | 80% | Email+password login/register/session/guards work; **OTP is dead code**, no forgot-password, weak password policy, self-role-escalation flaw |
| Products | 75% | List/detail/search/filter/pagination implemented; error-swallowing; `slug` fallback |
| Categories | 20% | Derived from `products.category` text; admin CRUD targets a non-existent/unverified `categories` table (contradiction) |
| Cart | 85% | Works; two implementations; pricing inconsistency in dead hook |
| Wishlist | 70% | Service + realtime context; `wishlist` table not in migrations |
| Checkout | 65% | Atomic RPC path good; insecure client fallback; no delivery/shipping selection UI (constants exist, unused); delivery hardcoded "Free" |
| Orders | 75% | History, detail, admin management, status updates |
| Payments | 10% | `paymentService` is a stub; `payments` table not in migrations; no M-Pesa/PSP; no verification |
| Admin Dashboard | 70% | Stats, products, orders, users, inventory, pickup-locations; **Settings is a placeholder** ("Configuration Module Offline") |
| Profiles | 70% | View/update; addresses service targets unverified `addresses` table |
| Search | 60% | `ilike` on name only; no full-text, no facets |
| Reviews | 5% | `StarRating` component only; no reviews table/flow |
| Notifications | 5% | Toasts only; no notification system |
| Analytics | 30% | Dashboard revenue chart (client-aggregated); no real analytics |
| Deployment | 10% | Build works; no CI/hosting/monitoring |
| Testing | 0% | None |
| Documentation | 40% | Structure exists; ~half empty; contradictions |

### Overall completion: **~45–50%**
A functional MVP skeleton with real auth/catalog/cart/checkout/admin, but payments, testing, deployment, several tables, and much documentation are missing or stubbed.

---

## PART 11 — Technical Debt

| Debt | Type | Severity |
|---|---|---|
| `profiles` role-escalation RLS | Security defect | Critical |
| Client-side order fallback (untrusted totals) | Security/design | High |
| Root `.gitignore` is a directory; `.env` committed | Config/secrets | High |
| Schema not in migrations (empty remote-schema dump) | Reproducibility | High |
| Navbar/Footer only on `/` (layout) + duplicate `/` route | UX bug | High |
| No indexes on FKs/search columns | Performance | High |
| `authService.js` invalid JS (Markdown fences) | Dead/broken code | Medium |
| Dead files: `api.js`, `lib/auth.js`, `hooks/use*`, `ProductsPage`, `OtpInput` | Dead code | Medium |
| Missing `/placeholder.png`; `getPublicUrl` bug | Runtime bug | Medium |
| Error-swallowing services | Reliability | Medium |
| Duplicate cart logic (context vs hook, inconsistent pricing) | Duplication | Medium |
| ESLint config missing → lint broken | Tooling | Medium |
| Categories: two competing models | Design | Medium |
| Mixed identifier casing (`"discountPrice"`) | DB naming | Medium |
| 28 `console.*`; no logger | Cleanliness | Low |
| Brand naming Babees vs Babis | Consistency | Low |
| `frontend/.agents/` skill docs committed in app | Bloat | Low |

**Refactoring priority:** (1) security RLS + order integrity, (2) Git hygiene + schema in migrations, (3) shared layout + delete dead code, (4) indexes + query fixes, (5) tooling/tests, (6) docs.

---

## PART 12 — Documentation Synchronization

| Document | State |
|---|---|
| `README.md` | **Needs Update** (references nonexistent `scripts/`, `.github/`; brand "Babees" vs code "Babis") |
| `00_PROJECT_VISION.md` | Accurate (high-level) |
| `01_ARCHITECTURE.md` | **Needs Update** — describes intended layers but omits actual data model, the layout wiring, and services split; no diagram |
| `03_Security.md` | **Missing** (empty) — and does not document the actual RLS model/flaw |
| `10_Final_Checklist.md` | **Missing** (empty) |
| `13_CODING_STANDARDS.md` | Accurate (generic); not enforced (no lint config) |
| `AI_COLLABORATION.md` | **Needs Update** — references non-matching doc names |
| `AUTOMATIONS.md` | Accurate as guidance; not automated (no CI) |
| `CHANGELOG.md` | **Outdated/Inaccurate** — claims v1.0 production release; reality is pre-MVP, 1 commit |
| `DECISIONS.md` | Mostly Accurate; ADR-014 folder list **Outdated**; missing ADRs for actual schema/data-model choices |
| `ENGINEERING.md` | Accurate (aspirational standards); partially unmet |
| `PROJECT_MASTER_PLAN.md` | Mostly Accurate (status flags roughly right); more current than CHANGELOG |
| `technical/02_Database.md` | **Missing** (empty) |
| `technical/04_Authentication.md` | **Missing** (empty; corrupt filename) |
| `technical/05_API.md` | **Missing** (empty) |
| `technical/06_Frontend.md` | **Missing** (empty) |
| `technical/07_Admin.md` | **Missing** (empty) |
| `technical/08_Deployment.md` | **Missing** (empty) |
| `technical/09_Testing.md` | **Missing** (empty) |
| `audits/01_Project_Audit.md` | **Missing** (empty; superseded by this document) |

---

## PART 13 — Engineering Scorecard (1–10)

| Dimension | Score | Rationale |
|---|---:|---|
| Architecture | 6 | Clean layering & splitting; undermined by schema drift, layout bug, dual implementations |
| Security | 4 | Good intent; critical privilege escalation + secrets/ignore issues |
| Frontend | 6 | Solid structure/design system; layout bug, dead code, no tests |
| Backend | 5 | Strong RPC/trigger; incomplete coverage, integrity gaps |
| Database | 5 | Good core; no indexes, not reproducible, naming issues |
| Supabase | 5 | Core RLS present; unverified tables/storage, config mismatches |
| Documentation | 4 | Good scaffold; half empty, contradictions, broken refs |
| Testing | 1 | None; lint broken |
| Maintainability | 6 | Readable, modular; debt from dead/duplicate code |
| Performance | 6 | Splitting works; query/image/caching gaps |
| Scalability | 5 | Postgres/Supabase scale; missing indexes/search block it |
| Production Readiness | 3 | Build works; no CI/monitoring/tests, security blockers |
| **Overall Engineering Quality** | **4.7** | Promising MVP with strong conventions, blocked by security, testing, and reproducibility gaps |

---

## PART 14 — Priority Roadmap
See `docs/NEXT_STEPS.md` for the full, effort-estimated, dependency-mapped roadmap (Critical → Low).

---

## PART 15 — Executive Summary

**Current state.** Babees Place is an early-stage (pre-MVP, single-commit) React + Supabase e-commerce app with a genuinely clean, well-documented engineering *intent*. The frontend builds successfully and implements auth, catalog, cart, checkout, orders, and an admin area. However, roughly half the documentation is empty, ~55% of the product is unbuilt or stubbed, and there are **critical security and reproducibility defects**.

**Biggest strengths.**
1. Clean, layered frontend architecture with route-level code splitting (build verified).
2. Strong security *conventions* documented (ADRs, RLS-first, DoD) and a well-designed atomic `place_order` RPC + auto-profile trigger.
3. Consistent, attractive design system (Tailwind tokens, reusable UI kit).

**Biggest weaknesses.**
1. **Critical privilege-escalation flaw** in the `profiles` RLS update policy (any user can self-promote to admin).
2. **Schema not reproducible** — `products` and 5 other tables are not in migrations; the "remote schema" migration is empty.
3. **Broken Git hygiene** — root `.gitignore` is a directory; `.env` is committed.
4. **No tests, broken lint, no CI/monitoring.**
5. **Site-wide layout bug** — navigation/footer render only on the home page.

**Top 10 priorities.**
1. Fix `profiles` role-escalation RLS (Critical).
2. Remove client-side order creation; enforce server-computed totals (Critical).
3. Fix `.gitignore` (real file), untrack `.env`, add `.env.example` (Critical).
4. `supabase db pull` → commit full schema; verify RLS on all tables (High).
5. Fix the shared-layout bug + remove duplicate route (High).
6. Add DB indexes (FKs, `products.category/slug`) + full-text search (High).
7. Delete dead/broken files; fix `getPublicUrl`; add `/placeholder.png` (High/Med).
8. Add ESLint config + CI (lint/build) and a Vitest+Playwright test baseline (High).
9. Fill empty technical docs; correct CHANGELOG/README; add ERD + architecture diagrams (Medium).
10. Implement real payments (M-Pesa via Edge Function) + monitoring/logging (Medium, pre-launch).

**Estimated time to production readiness.** With one focused engineer: **~6–9 weeks** — ~1 week security/Git blockers, ~1–2 weeks schema/migrations/RLS + indexes, ~1 week layout/dead-code/bug fixes, ~1–2 weeks testing/CI, ~2–3 weeks payments + monitoring + docs + hardening.

**Estimated project completion.** **~45–50%.**
