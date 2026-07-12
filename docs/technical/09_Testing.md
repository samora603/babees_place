# Testing — Technical Reference

Status: Updated during Phase 1 (testing foundation established).
Source of truth: `frontend/package.json`, `frontend/vitest.config.js`, `frontend/playwright.config.js`, and the test files under `frontend/src/**` and `frontend/e2e/`.

---

## 1. Current state
- ✅ **Test framework installed** — Vitest + React Testing Library + jsdom (unit/component) and Playwright (e2e).
- ✅ **Smoke tests present and passing** (`npm run test` → 18 tests):
  - `src/utils/helpers.test.js` — `formatCurrency`, `truncate`, `getPrimaryImage`, `discountPercent`, `normalizePhone`.
  - `src/components/ui/Button.test.jsx` — render, disabled-while-loading, click handler.
  - `src/test/routing.test.jsx` — app startup + routing + auth entry points (`/login`, `/register`, 404) with a mocked Supabase client (`src/test/supabaseMock.js`).
- ✅ **Lint gate restored** — `npm run lint` runs against `.eslintrc.cjs` and passes (0 errors).
- 🟡 **Playwright e2e is opt-in** — `frontend/e2e/smoke.spec.js` exists but is NOT part of the required CI gate: it needs `npx playwright install` and valid `VITE_SUPABASE_*` values for the preview build. Run locally with `npm run test:e2e`.
- 🟡 **Database/RLS policy tests still missing** (see §3).

**Automated coverage: smoke-level.** Deeper service/RLS coverage is still outstanding.

## 2. Critical areas that most need tests (risk order)
1. `place_order` RPC — totals, stock validation, atomicity.
2. RLS policies — especially that a `user` **cannot** change `profiles.role`, and cannot read other users' orders.
3. Auth flows + route guards (`ProtectedRoute`, `AdminRoute`).
4. Cart math (two implementations disagree on pricing).
5. Order mapping / history (`orderService.mapOrder`).

## 3. Recommended strategy (Phase 1+)

### Unit / component — Vitest + React Testing Library
- Helpers: `formatCurrency`, `normalizePhone`, `discountPercent`, `getPrimaryImage`.
- Services: mock `supabase-js`; assert query shapes and error propagation.
- Components: `Button`, `Pagination`, `QuantitySelector`, guards.

### Database / policy — pgTAP or seeded test project
- Assert RLS: role escalation blocked, cross-user reads blocked, order-item ownership.

### Integration / e2e — Playwright
- Happy path: browse → add to cart → checkout → order visible.
- Admin: login → manage product/order; non-admin blocked from `/admin`.

### CI gate
- `lint` + `unit test` + `build` run on every push/PR via `.github/workflows/ci.yml` and fail the workflow on any error. Playwright e2e is intentionally excluded from the required gate (see §1).

## 4. Scripts (implemented in Phase 1)
```jsonc
// frontend/package.json
"lint": "eslint . --ext js,jsx --report-unused-disable-directives",
"test": "vitest run",
"test:watch": "vitest",
"test:e2e": "playwright test"
```

## 5. Definition of Done alignment
`docs/ENGINEERING.md` and `PROJECT_MASTER_PLAN.md` require "no lint errors" and "tested code". As of Phase 1 both are now achievable: an ESLint config exists and lint passes, and a Vitest/RTL smoke suite runs green. Remaining gap: meaningful service-layer and RLS/policy test coverage.
