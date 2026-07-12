# Git Commit Plan — Remaining Uncommitted Work

**Date:** 2026-07-12
**Branch:** `main`
**Scope:** All uncommitted changes **except** the already-staged Phase 1.7A baseline-adoption
commit (see `Phase1_7A_Checkpoint.md`).
**Status:** Analysis only. **Nothing staged or committed.** No files modified except this plan.

---

## 0. Method & constraints

- The repo has a single prior commit (`a4e3e9e Initial commit`); everything below has
  accumulated across Phases 0 → 1.6 and was never committed.
- **Atomic constraint:** `frontend/package.json` + `frontend/package-lock.json` contain
  interleaved changes for dependency removals **and** linting/formatting **and** testing
  tooling. They cannot be split without editing them, so they anchor a single **build** commit
  that the test/CI/code commits depend on.
- **`frontend/.env` is currently TRACKED again** (it was un-staged during checkpoint prep). The
  housekeeping commit must re-run `git rm --cached frontend/.env` to untrack the secret.
- The 9 staged Phase 1.7A files are **excluded** from every group below.

### Quarantine — do NOT commit
| Path | Reason | Action |
|---|---|---|
| `docs/operations/.~lock.Database_Reconciliation_Runbook.md#` | LibreOffice lock file — the runbook is open in an editor | Close the editor; add `.~lock.*#` to `.gitignore`; never stage |

---

## Commit overview

| # | Type / scope | Summary | Depends on |
|---|---|---|---|
| C1 | `chore(repo)` | ignore rules, env template, untrack `.env` secret | — |
| C2 | `docs(project)` | restructure core & technical documentation | — |
| C3 | `docs(engineering)` | audit reports + schema reconciliation package | — |
| C4 | `build(tooling)` | ESLint/Prettier/EditorConfig/Husky + dependency changes | C1 |
| C5 | `test` | unit, smoke, and e2e tests | C4 |
| C6 | `fix(security)` | server-side orders + prevent profile privilege escalation | C4 |
| C7 | `refactor(frontend)` | remove dead code + fix lint violations | C4 |
| C8 | `ci` | GitHub Actions lint/test/build workflow | C4, C5, C6, C7 |

---

## C1 — `chore(repo): add ignore rules, env template, and untrack committed secret`

**Files**
- `.gitignore` (new, root)
- `frontend/.gitignore` (new)
- `frontend/.env.example` (new)
- `frontend/.env` → **`git rm --cached frontend/.env`** (untrack; keep on disk)

**Why together:** repository hygiene foundation. Ignore rules must exist before other commits
so build artifacts / env files aren't accidentally tracked; the `.env` secret is untracked and
replaced by a safe template in the same change.

**Dependencies:** none. **Execute first.**

**Message**
```
chore(repo): add ignore rules, env template, and untrack committed secret

- add root and frontend .gitignore (node_modules, build, env, editor/OS files, test artifacts)
- add frontend/.env.example as a safe template
- git rm --cached frontend/.env to stop tracking secrets (Phase 0 housekeeping)
```

---

## C2 — `docs(project): restructure core and technical documentation`

**Files**
- Modified: `README.md`, `docs/03_Security.md`, `docs/10_Final_Checklist.md`
- Deleted (old/malformed numbered docs): `docs/01_Project_Audit.md`, `docs/02_Database.md`,
  `docs/04_Authentication.md\n` (malformed filename), `docs/05_API.md`, `docs/06_Frontend.md`,
  `docs/07_Admin.md`, `docs/08_Deployment.md`, `docs/09_Testing.md`
- New (top-level): `docs/00_PROJECT_VISION.md`, `docs/01_ARCHITECTURE.md`,
  `docs/13_CODING_STANDARDS.md`, `docs/AI_COLLABORATION.md`, `docs/AUTOMATIONS.md`,
  `docs/CHANGELOG.md`, `docs/DECISIONS.md`, `docs/ENGINEERING.md`,
  `docs/PROJECT_MASTER_PLAN.md`, `docs/NEXT_STEPS.md`
- New (technical): `docs/technical/02_Database.md`, `04_Authentication.md`, `05_API.md`,
  `06_Frontend.md`, `07_Admin.md`, `08_Deployment.md`, `09_Testing.md`
- New (architecture): `docs/architecture/Current_Project_Structure.md`

**Why together:** the Phase 0 documentation restructure — retire the flat/malformed numbered
docs and replace them with the organized `docs/technical/` set plus the core project docs
(vision, architecture, engineering, standards, changelog). One cohesive documentation baseline.

**Dependencies:** none (content-independent of code). Best committed early.

**Message**
```
docs(project): restructure core and technical documentation

- remove flat/malformed numbered docs (incl. corrupted 04_Authentication filename)
- add docs/technical/* and docs/architecture/ structure
- add project vision, architecture, engineering, coding standards, changelog, decisions
- update README, security overview, and final checklist to match implementation
```

---

## C3 — `docs(engineering): add audit reports and schema reconciliation package`

**Files**
- `docs/audits/*` (all new, **excluding** the 3 staged Phase 1.7A docs):
  `01_Project_Audit.md`, `PROJECT_AUDIT.md`, `SECURITY_AUDIT.md`, `FRONTEND_AUDIT.md`,
  `DATABASE_AUDIT.md`, `SUPABASE_AUDIT.md`, `PERFORMANCE_AUDIT.md`, `PRODUCTION_READINESS.md`,
  `Production_Readiness.md`, `Documentation_Audit.md`, `Dependency_Audit.md`,
  `Environment_Audit.md`, `Frontend_Health_Report.md`, `Supabase_Health_Report.md`,
  `Security_Baseline.md`, `Technical_Debt_Register.md`, `Phase0_Repository_Audit.md`,
  `Phase0_Remediation_Plan.md`, `Phase0_Final_Report.md`, `Phase1_Stabilization_Report.md`,
  `Phase1_Final_Closure_Report.md`, `Phase1_5_Readiness_Report.md`,
  `Frontend_Database_Compatibility.md`, `Phase1_6_Execution_Readiness.md`
- `docs/database/*` (new, **excluding** staged `Migration_History.md`):
  `Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`, `Final_Canonical_Schema.md`,
  `Reconciliation_Decision_Log.md`, `Migration_Strategy.md`, `Baseline_Migration_Verification.md`,
  `generated_baseline/001_initial_schema.sql`
- `docs/adr/ADR-001-Database-Reconciliation.md`
- `docs/operations/Database_Reconciliation_Runbook.md` (**not** the `.~lock` file)

**Why together:** all evidence-based engineering analysis and the schema-reconciliation design
package (audits → comparison → canonical schema → strategy → ADR → runbook → readiness). They
cross-reference each other and represent the planning output that justifies the 1.7A baseline.

**Dependencies:** conceptually follows the 1.7A baseline commit and C2, but git-independent.
*Optional split* if finer granularity is desired: `docs(audit)` (audits) + `docs(database)`
(database + adr + operations) — would make the plan 9 commits.

**Message**
```
docs(engineering): add audit reports and schema reconciliation package

- add Phase 0/1/1.5/1.6 audit and readiness reports
- add schema comparison matrix, canonical schema, decision log, and migration strategy
- add ADR-001 (database reconciliation) and the reconciliation operational runbook
- include read-only generated baseline artifact for provenance
```

---

## C4 — `build(tooling): configure lint/format/hooks and update dependencies`

**Files**
- `frontend/package.json`, `frontend/package-lock.json` (dep add: prettier, husky, lint-staged,
  vitest, RTL, jsdom, playwright; dep remove: axios, react-image-gallery; script updates)
- `.editorconfig`
- `frontend/.eslintrc.cjs`, `frontend/.eslintignore`
- `frontend/.prettierrc.json`, `frontend/.prettierignore`
- `.husky/pre-commit`
- `frontend/vitest.config.js`, `frontend/playwright.config.js`

**Why together:** `package.json`/lock is atomic and encodes exactly the dev-tooling and test
dependencies these config files rely on. Grouping the manifest with all quality/test
configuration keeps the tree installable and lint/test-runnable at this commit.

**Dependencies:** C1 (ignore rules). **Prerequisite for C5, C6, C7, C8.**

**Message**
```
build(tooling): configure lint/format/hooks and update dependencies

- add ESLint, Prettier, EditorConfig, Husky pre-commit + lint-staged
- add Vitest and Playwright configuration
- add test/tooling dev dependencies; remove unused axios and react-image-gallery
- update npm scripts (lint, format, test, test:watch, test:e2e)
```

---

## C5 — `test: add unit, smoke, and e2e tests`

**Files**
- `frontend/src/test/setup.js`, `frontend/src/test/supabaseMock.js`, `frontend/src/test/routing.test.jsx`
- `frontend/src/components/ui/Button.test.jsx`
- `frontend/src/utils/helpers.test.js`
- `frontend/e2e/smoke.spec.js`

**Why together:** the actual test suites + shared test harness (setup, Supabase mock) that
depend on the frameworks configured in C4.

**Dependencies:** C4 (test deps + vitest/playwright config).

**Message**
```
test: add unit, smoke, and e2e tests

- unit tests for helpers and Button
- routing/auth-entry smoke test with a chainable Supabase mock
- Playwright e2e smoke spec (home, login, 404)
```

---

## C6 — `fix(security): enforce server-side orders and prevent profile privilege escalation`

**Files**
- `frontend/src/context/AuthContext.jsx` (strip privileged fields from profile updates)
- `frontend/src/services/userService.js` (strip privileged fields)
- `frontend/src/pages/Checkout.jsx` (remove client-side order fallback)
- `frontend/src/services/orderService.js` (remove `createOrderFromCart`; use `place_order` RPC only)

**Why together:** the Phase 1 Critical/High security remediations — role-escalation prevention
and forcing order creation through the atomic server RPC. A single security-focused change set.

**Dependencies:** C4 (so lint passes on the changed files); logically independent of C7.

**Message**
```
fix(security): enforce server-side orders and prevent profile privilege escalation

- strip role/is_admin/id/created_at from client profile updates (AuthContext, userService)
- remove insecure client-side order creation fallback
- route checkout exclusively through the atomic place_order RPC
```

---

## C7 — `refactor(frontend): remove dead code and fix lint violations`

**Files**
- Deleted dead code: `frontend/src/components/auth/OtpInput.jsx`,
  `frontend/src/hooks/useAuth.js`, `useCart.js`, `useProducts.js`, `useWishlist.js`,
  `frontend/src/lib/auth.js`, `frontend/src/pages/ProductsPage.jsx`,
  `frontend/src/services/api.js`, `frontend/src/services/authService.js`
- Modified: `frontend/src/App.jsx` (remove duplicate `/` route),
  `frontend/src/pages/NotFound.jsx` (escape entities — lint fix),
  `frontend/src/pages/ProductDetail.jsx` (refactor `finally` block — lint fix)

**Why together:** non-behavioral cleanup — remove confirmed-unused modules and resolve the
ESLint errors so the tree lints clean. Kept separate from C6 so security changes are auditable
in isolation.

**Dependencies:** C4 (ESLint config defines the violations being fixed).

**Message**
```
refactor(frontend): remove dead code and fix lint violations

- delete unused hooks, services, auth OtpInput, and unrouted ProductsPage
- remove duplicate root route in App.jsx
- fix unescaped entities (NotFound) and unsafe finally (ProductDetail)
```

---

## C8 — `ci: add GitHub Actions workflow for lint, test, and build`

**Files**
- `.github/workflows/ci.yml`

**Why together:** CI definition on its own; it exercises lint (C4/C7), tests (C5), and build.

**Dependencies:** C4, C5, C6, C7. **Commit/push last** so the first CI run executes against a
tree that lints clean, tests green, and builds.

**Message**
```
ci: add GitHub Actions workflow for lint, test, and build

- run lint, unit tests, and production build on push/PR to main
- Node 20 with npm caching; fail fast on any stage
```

---

## Recommended execution order

```
C1  chore(repo)        ← ignore rules first (nothing unwanted gets tracked)
C2  docs(project)      ← independent; commit early
C3  docs(engineering)  ← independent
C4  build(tooling)     ← deps/config; unlocks code + tests + ci
C6  fix(security)      ← code stable before CI runs
C7  refactor(frontend) ← clears lint errors so CI lint stage is green
C5  test               ← suites present before CI runs them
C8  ci                 ← LAST: first CI run sees a green tree
```

Rationale: C1 establishes ignore hygiene; docs (C2, C3) are dependency-free and safe anytime;
C4 must precede everything code/test/CI-related; C6 + C7 bring the code to a lint-clean,
secure state; C5 adds the suites; C8 is last so CI never runs against a red tree.

---

## Coverage check (every remaining change is assigned)

| Group | Files |
|---|---:|
| C1 hygiene | 3 new + 1 untrack |
| C2 project docs | 3 M + 8 D + 10 new + 7 technical + 1 architecture = 29 |
| C3 engineering docs | 24 audits + 7 database + 1 adr + 1 operations = 33 |
| C4 tooling | 2 manifest + 8 config = 10 |
| C5 tests | 6 |
| C6 security | 4 |
| C7 refactor | 9 D + 3 M = 12 |
| C8 ci | 1 |
| **Quarantined (not committed)** | `docs/operations/.~lock.*#` |
| **Excluded (already staged)** | 9 Phase 1.7A files |

All remaining tracked + untracked changes are accounted for; nothing is left ungrouped except
the quarantined editor lock file.

---

## Final notes / manual actions
1. **Close the runbook in your editor** to clear `docs/operations/.~lock.Database_Reconciliation_Runbook.md#`; add `.~lock.*#` to `.gitignore`.
2. **Commit the staged Phase 1.7A checkpoint first** (already staged) if not yet done, then proceed C1 → C8.
3. C1 requires re-running `git rm --cached frontend/.env` (it is currently tracked again).
4. This plan stages/commits nothing — awaiting review.
