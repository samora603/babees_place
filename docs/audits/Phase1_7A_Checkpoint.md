# Phase 1.7A — Baseline Checkpoint

**Date:** 2026-07-12
**Branch:** `main`
**Prepared by:** Lead Architect (checkpoint preparation only)
**State:** Commit **prepared, not created**. Tag **recommended, not created**.
**Guarantees:** No live DB changes · No frontend changes · No migrations executed · No commit/tag created automatically.

---

## 1. Milestone Summary

This checkpoint marks the end of all planning and repository reconciliation work
(Phases 0 → 1.7A) and the adoption of the **verified live schema as the authoritative
migration baseline**. From here, all future database and implementation work proceeds
from `supabase/migrations/001_initial_schema.sql`.

The commit is intentionally **scoped to the Phase 1.7A baseline-adoption milestone only**.
The repository currently has a large body of *uncommitted prior-phase work* (Phases 0–1.6:
documentation, tooling, and Phase 1 frontend stabilization) that predates this task. Per the
checkpoint instructions, that work is **not** staged here and is reported below so it can be
committed separately with appropriate messages.

---

## 2. Repository Review — Full Change Classification

**Repo history:** only one prior commit (`a4e3e9e Initial commit`). Everything below is
uncommitted. Total changes: **68**.

### 2A. Phase 1.7A — Migration (STAGE)
| File | Change | Class |
|---|---|---|
| `supabase/migrations/001_initial_schema.sql` | new (promoted baseline) | Migration |
| `supabase/migrations/archive/001_schema_rls_place_order.sql` | renamed from `migrations/` | Migration |
| `supabase/migrations/archive/20260617042152_remote_schema.sql` | renamed from `migrations/` | Migration |
| `supabase/migrations/archive/002_phase1_security_hardening.sql` | moved into archive | Migration |
| `supabase/migrations/archive/003_phase1_indexes_constraints.sql` | moved into archive | Migration |
| `supabase/migrations/archive/README.md` | new | Migration/Doc |

### 2B. Phase 1.7A — Documentation (STAGE)
| File | Change | Class |
|---|---|---|
| `docs/database/Migration_History.md` | new | Documentation |
| `docs/audits/Phase1_7A_Baseline_Adoption_Report.md` | new | Documentation |
| `docs/audits/Phase1_7A_Checkpoint.md` | new (this file) | Documentation |

### 2C. Intentionally EXCLUDED — prior-phase work (report only, do NOT stage)

**Repository housekeeping (Phase 0):**
- `frontend/.env` — staged deletion (untrack secret). *Unstaged by this checkpoint;* belongs to a Phase 0 security-housekeeping commit.

**Documentation (Phases 0 / 1.5 / 1.6):**
- Modified: `README.md`, `docs/03_Security.md`, `docs/10_Final_Checklist.md`.
- Deleted (Phase 0 restructure): `docs/01_Project_Audit.md`, `02_Database.md`, `"04_Authentication.md\n"`, `05_API.md`, `06_Frontend.md`, `07_Admin.md`, `08_Deployment.md`, `09_Testing.md`.
- New: `docs/00_PROJECT_VISION.md`, `01_ARCHITECTURE.md`, `13_CODING_STANDARDS.md`, `AI_COLLABORATION.md`, `AUTOMATIONS.md`, `CHANGELOG.md`, `DECISIONS.md`, `ENGINEERING.md`, `NEXT_STEPS.md`, `PROJECT_MASTER_PLAN.md`.
- New dirs: `docs/adr/`, `docs/architecture/`, `docs/operations/`, `docs/technical/`.
- `docs/database/` **other** files (Phase 1.5/1.6): `Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`, `Final_Canonical_Schema.md`, `Reconciliation_Decision_Log.md`, `Migration_Strategy.md`, `Baseline_Migration_Verification.md`, `generated_baseline/`.
- `docs/audits/` **other** files (Phases 0/1/1.5/1.6): all audit + phase reports.

**Configuration / tooling (Phase 1):**
- `.editorconfig`, `.github/`, `.husky/`, `.gitignore` (root).
- `frontend/.eslintignore`, `.eslintrc.cjs`, `.gitignore`, `.prettierignore`, `.prettierrc.json`, `playwright.config.js`, `vitest.config.js`.
- `frontend/package.json`, `frontend/package-lock.json` (modified).

**Frontend code (Phase 1 stabilization):**
- Modified: `App.jsx`, `context/AuthContext.jsx`, `pages/Checkout.jsx`, `pages/NotFound.jsx`, `pages/ProductDetail.jsx`, `services/orderService.js`, `services/userService.js`.
- Deleted: `components/auth/OtpInput.jsx`, `hooks/useAuth.js`, `useCart.js`, `useProducts.js`, `useWishlist.js`, `lib/auth.js`, `pages/ProductsPage.jsx`, `services/api.js`, `services/authService.js`.
- New tests: `components/ui/Button.test.jsx`, `src/test/`, `utils/helpers.test.js`, `e2e/`.

### Unexpected / unrelated changes
None unexpected. The only pre-staged unrelated item is the `frontend/.env` deletion (Phase 0),
which this checkpoint **unstages** to keep the milestone clean.

---

## 3. Baseline Verification Results

| Check | Result |
|---|---|
| `supabase/migrations/001_initial_schema.sql` is the authoritative baseline | ✅ Present; 7 `CREATE TABLE`, faithful live snapshot + provenance header |
| Historical migrations archived (not deleted) | ✅ 4 files under `supabase/migrations/archive/` + `README.md` |
| Pristine generated artifact preserved | ✅ `docs/database/generated_baseline/001_initial_schema.sql` unchanged |
| Documentation references new migration history | ✅ `Migration_History.md` + `Phase1_7A_Baseline_Adoption_Report.md` + SQL header |
| Active sequence coherent (single baseline, no dup versions) | ✅ only `001_initial_schema.sql` active |
| No active migration depends on fictional objects | ✅ fictional files isolated in `archive/` |
| Repository internally consistent | ✅ cross-references resolve on disk |

---

## 4. Files to be Staged (checkpoint)

```
supabase/migrations/001_initial_schema.sql
supabase/migrations/archive/001_schema_rls_place_order.sql   (rename)
supabase/migrations/archive/20260617042152_remote_schema.sql (rename)
supabase/migrations/archive/002_phase1_security_hardening.sql
supabase/migrations/archive/003_phase1_indexes_constraints.sql
supabase/migrations/archive/README.md
docs/database/Migration_History.md
docs/audits/Phase1_7A_Baseline_Adoption_Report.md
docs/audits/Phase1_7A_Checkpoint.md
```

## 5. Files Intentionally Excluded
All prior-phase work in §2C (frontend stabilization, tooling/config, and Phases 0–1.6
documentation), plus the Phase 0 `frontend/.env` untracking. These should land in their own
commits (suggested: a Phase 0/1 docs+tooling commit and a Phase 1 frontend-stabilization
commit) — out of scope for this baseline checkpoint.

---

## 6. Recommended Commit Message (prepared, not created)

```
chore(database): adopt live schema as migration baseline

- adopt verified live schema as authoritative baseline
- archive fictional and deprecated migrations
- preserve historical migration artifacts
- synchronize migration history documentation
- complete repository baseline adoption (Phase 1.7A)
```

## 7. Recommended Tag (not created)

**`v0.2.0-baseline`**

Rationale:
- **`0.x`** — project is pre-production / pre-1.0: no deployment, checkout RPC not yet on live, reconciliation not yet executed. A `1.0.0` tag would misrepresent maturity.
- **minor bump `0.1 → 0.2`** — the initial commit is the effective `0.1.0`; adopting a verified, version-controlled schema baseline is a meaningful, backward-compatible milestone (new capability: reproducible schema foundation), which SemVer models as a minor increment.
- **`-baseline` pre-release label** — signals this specific milestone (schema baseline established) and that it is a foundation checkpoint, not a feature release.

Create manually after committing, e.g.: `git tag -a v0.2.0-baseline -m "Database schema baseline (Phase 1.7A)"`.

---

## 8. Next Implementation Phase

**Phase 1.7B — Live baseline adoption + first forward migration authoring.**
Adopt the baseline on live (`supabase migration repair --status applied 001`, confirm clean
`supabase db diff`), then author `M1..M8` (per `Migration_Strategy.md`) against the baseline,
following `Database_Reconciliation_Runbook.md`.

---

## 9. Remaining Manual Actions (before migrations are authored)

1. **Run `migration repair` on live** so the remote history records the baseline; then confirm `supabase db diff --linked` is clean. (Requires project credentials — not done here.)
2. **Four read-only verifications:** product `id` uniqueness, cart/wishlist duplicate rows, `storage.buckets` for `products`, distinct `profiles.role` values.
3. **Approvals** for the destructive/normalizing migrations `M5`/`M6`/`M7` and Phase 2 feature scope (`payments`/`pickup_locations`/`addresses`).
4. Decide whether to keep the numeric `001_` prefix or re-version to a timestamp before first `db push` (docs assume `001_`).

---

## Final Validation

- ✅ Repository ready for its first implementation phase (after §9 manual steps).
- ✅ No live database changes occurred.
- ✅ No frontend changes occurred.
- ✅ No migrations were executed.
- ✅ No commit or tag was created automatically.

**Stop:** checkpoint prepared. Awaiting human approval to commit and tag.
