# Phase 0 — Repository Health Audit

Auditor: Lead Software Architect / Principal Engineer
Date: 2026-07-12
Scope: full repository (`docs/`, `frontend/`, `supabase/`, Git state).
Method: evidence-based static inspection + verified build/lint. The live Supabase project was not accessed (remote-only facts flagged UNVERIFIED).

Format per finding: **Finding · Severity · Evidence · Recommendation · Resolution**.
Resolution states: **RESOLVED** (fixed in Phase 0), **DOCUMENTED** (left in place, tracked for later), or **OPEN**.

---

## R-1. Root `.gitignore` was a directory, not a file
- **Severity:** High
- **Evidence:** `stat -c '%F' .gitignore` → `directory`; `git ls-files .gitignore/` empty. No repo-level ignore rules existed.
- **Recommendation:** Replace with a real ignore file covering deps, build output, env, logs, editor/OS files.
- **Resolution:** **RESOLVED** — removed the empty directory (`rmdir .gitignore`) and created a proper root `.gitignore`; verified `stat` now reports `regular file` and `git check-ignore frontend/node_modules` passes.

## R-2. Corrupted documentation filename (embedded newline)
- **Severity:** Medium
- **Evidence:** `ls docs/technical | cat -A` → `04_Authentication.md\n$`; `wc` failed on `docs/technical/04_Authentication.md`.
- **Recommendation:** Rename to `04_Authentication.md`.
- **Resolution:** **RESOLVED** — deleted the 0-byte malformed file and created a properly named, populated `docs/technical/04_Authentication.md`.

## R-3. `frontend/.env` tracked in Git
- **Severity:** High (practice) / Low (impact today)
- **Evidence:** `git ls-files frontend/.env` returned the file; decoded JWT payload shows `"role":"anon"` (public key, **not** service-role).
- **Recommendation:** Untrack, ignore, and provide `.env.example`.
- **Resolution:** **RESOLVED** — `git rm --cached frontend/.env` (file kept on disk), added ignore rules + `frontend/.env.example`; verified `git check-ignore` passes and file is no longer tracked.

## R-4. Empty engineering/technical documents
- **Severity:** Medium
- **Evidence:** `find docs -type f -empty` previously returned 9 files (all `docs/technical/*`, `03_Security.md`, `10_Final_Checklist.md`, `audits/01_Project_Audit.md`).
- **Recommendation:** Populate with accurate starter content reflecting current implementation.
- **Resolution:** **RESOLVED** — all populated; `find docs -type f -empty` now returns nothing.

## R-5. Database schema not reproducible from migrations
- **Severity:** High
- **Evidence:** `supabase/migrations/20260617042152_remote_schema.sql` is **0 bytes**; migration `001` defines only `profiles/orders/order_items/cart`; code references `products, categories, wishlist, payments, pickup_locations, addresses`.
- **Recommendation:** Generate a baseline via `supabase db pull` (do **not** hand-write speculative migrations).
- **Resolution:** **DOCUMENTED / OPEN** — recorded here, in `Supabase_Health_Report.md`, `technical/02_Database.md`, and Technical Debt Register. Not fabricated per rules.

## R-6. Dead / unused source files
- **Severity:** Medium
- **Evidence (import search):** `services/api.js` (no `services/api` imports), `lib/auth.js`, `hooks/useAuth.js`, `hooks/useCart.js`, `hooks/useWishlist.js`, `pages/ProductsPage.jsx` (unrouted), `components/auth/OtpInput.jsx` — none referenced.
- **Recommendation:** Remove after confirming no external references (Phase 1).
- **Resolution:** **DOCUMENTED** — not deleted (rule: delete only when certain). Listed in Frontend Health Report + Technical Debt Register as removal candidates.

## R-7. Broken source file (`authService.js`)
- **Severity:** Medium
- **Evidence:** `frontend/src/services/authService.js` contains literal Markdown code fences (```` ``` ````) inside a `.js` file (lines 7,17,24,38,60,72) → invalid JavaScript. Unused, so it does not break the build.
- **Recommendation:** Fix or delete; it should not ship.
- **Resolution:** **DOCUMENTED / OPEN** — left in place (conservative), flagged as High-confidence removal candidate.

## R-8. Duplicate Supabase client modules
- **Severity:** Low
- **Evidence:** `lib/supabaseClient.js` (real client) + `lib/supabase.js` (re-export). Services import from both paths.
- **Recommendation:** Standardize on one import path.
- **Resolution:** **DOCUMENTED** — the re-export is intentional/harmless; consolidate in Phase 1.

## R-9. Missing static asset `/placeholder.png`
- **Severity:** Medium
- **Evidence:** `ls public/` → `assets`, `hero_carousel` only; code references `/placeholder.png` as image fallback in `CartContext`, `orderService.mapOrder`, `helpers.getPrimaryImage`.
- **Recommendation:** Add the asset (or change fallback).
- **Resolution:** **DOCUMENTED / OPEN** — adding an image asset is a Phase 1 fix (not created here to avoid binary generation).

## R-10. Empty placeholder directories under `docs/`
- **Severity:** Low
- **Evidence:** `find docs -type d -empty` → `docs/operations`, `docs/prompts`, `docs/references`, `docs/testing`. Untracked (Git omits empty dirs).
- **Recommendation:** Either populate, add `.gitkeep`, or remove.
- **Resolution:** **DOCUMENTED** — left in place (uncertain intent); flagged for cleanup.

## R-11. Non-application tooling committed inside app tree
- **Severity:** Low
- **Evidence:** `frontend/.agents/` (40 tracked files, ~200K, Supabase skill docs) + `frontend/skills-lock.json`; `frontend/.qodo/` (untracked).
- **Recommendation:** Move tooling out of the app tree or ignore; keep the repo app-focused.
- **Resolution:** **DOCUMENTED** — not obsolete (reference material); relocate/ignore in Phase 1.

## R-12. Workspace path casing mismatch
- **Severity:** Low
- **Evidence:** Tooling was configured for `Babees_Place` but the directory is `babees_place`; case-sensitive path tools failed until corrected.
- **Recommendation:** Standardize on the lowercase directory name in tooling/config.
- **Resolution:** **DOCUMENTED**.

## R-13. Naming consistency: "Babees" vs "Babis"
- **Severity:** Low
- **Evidence:** docs say "Babees Place"; `package.json` name `babis-place-frontend`, migration header and `Login.jsx` say "Babis". `grep "Babis" src` = 5 hits, `"Babees"` = 0.
- **Recommendation:** Pick one canonical brand and align code + docs.
- **Resolution:** **DOCUMENTED** — README now carries an explicit naming note; reconciliation deferred (would touch working code).

---

## Structure & naming (summary)
- ✅ `frontend/src` layout is clean and matches documented architecture (components/pages/context/hooks/services/lib/utils).
- ✅ No OS/editor/log artifacts (`.DS_Store`, `*.log`, `*.swp`) found.
- ✅ No circular dependency between services and contexts (services do not import contexts).
- ✅ Production build succeeds; ❌ lint is non-functional (no ESLint config) — see Frontend Health Report.
- Tracked file count: 136 (pre-Phase-0 index).

## Scorecard
| Aspect | Before Phase 0 | After Phase 0 |
|---|---|---|
| Git hygiene | 2/10 | 8/10 |
| Filename/structure integrity | 5/10 | 8/10 |
| Documentation completeness | 4/10 | 7/10 |
| Dead code / clutter | 5/10 | 5/10 (documented, not removed) |
| Schema reproducibility | 2/10 | 2/10 (documented; needs `db pull`) |
| **Repository health (overall)** | **4/10** | **7/10** |
