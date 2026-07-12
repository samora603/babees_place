# Phase 0 — Dependency Audit

Auditor: Principal Engineer
Date: 2026-07-12
Scope: `frontend/package.json` (only package manifest in the repo).
Method: import-graph analysis (`grep` of `src/`), `npm outdated`, install warnings. Per Phase 0 rules, **no packages were upgraded**.

---

## 1. Declared dependencies vs actual usage

| Package | Declared | Imported in `src/`? | Verdict |
|---|---|---|---|
| `react` | ✅ | ✅ (33) | Used |
| `react-dom` | ✅ | ✅ | Used |
| `react-router-dom` | ✅ | ✅ (28) | Used |
| `react-icons` | ✅ | ✅ (34) | Used |
| `react-hot-toast` | ✅ | ✅ (13) | Used |
| `clsx` | ✅ | ✅ (4) | Used |
| `swiper` | ✅ | ✅ (Hero.jsx, index.css) | Used |
| `recharts` | ✅ | ✅ (AdminDashboard.jsx) | Used |
| `@supabase/supabase-js` | ✅ | ✅ | Used (core) |
| `axios` | ✅ | ⚠️ only in **dead** `services/api.js` | **Effectively unused** |
| `react-image-gallery` | ✅ | ❌ (`grep` = 0 hits) | **Unused** |

DevDependencies (`@types/react*`, `@vitejs/plugin-react`, `autoprefixer`, `eslint`, `eslint-plugin-react`, `eslint-plugin-react-hooks`, `postcss`, `tailwindcss`, `vite`) are all part of the build/lint toolchain. Note: `@types/react*` are present but the code is plain JSX (no TypeScript) — they only help editor tooling.

## 2. Unused dependencies (candidates for removal)
| Package | Reason | Recommendation |
|---|---|---|
| `react-image-gallery` | No import anywhere | Remove (Phase 1) after confirming no planned use |
| `axios` | Only imported by dead `services/api.js` | Remove together with the dead file |

> Not removed in Phase 0 (rule: don't delete unless certain; both are low-risk but tied to dead-code cleanup). Tracked in Technical Debt Register.

## 3. Missing dependencies
- **None.** Every external import in `src/` resolves to a declared dependency (verified via import extraction). No "imported-but-undeclared" packages.

## 4. Duplicate packages
- No duplicate/conflicting declarations in `package.json`. (A full `npm ls` de-dupe review of the transitive tree was not exhaustively performed; `package-lock.json` is present and should be the source of truth for transitive resolution.)

## 5. Deprecated packages
Reported by `npm install`:
- `eslint@8.57.1` — **deprecated** (v8 is end-of-life; latest is 9.x).
- Transitive: `inflight@1.0.6`, `glob@7.2.3`, `rimraf@3.0.2`, `@humanwhocodes/*` — pulled in by the eslint 8 toolchain.
- **Recommendation:** address as part of adding an ESLint configuration (either stay on 8 with a legacy `.eslintrc` short-term, or move to ESLint 9 flat config). Not urgent for runtime; it affects tooling only.

## 6. Version status (`npm outdated`)
Current versions are stable and internally consistent (React 18.3, Router 6.30, Vite 5.4, Tailwind 3.4). Newer majors exist (React 19, Vite 6, Tailwind 4, recharts 3, swiper 14, react-icons 5) but **upgrading is out of scope for Phase 0** and should be a deliberate, tested effort in a later phase.

## 7. Security
- No `npm audit` output was captured in this pass; **run `npm audit` in CI** once CI exists (see Production Readiness).
- No dependency currently pins a known-malicious or abandoned runtime package; `axios` and `swiper`/`recharts` are actively maintained.

## 8. Recommendations (priority)
1. Add an ESLint config so lint runs (unblocks the quality gate); decide eslint 8-legacy vs 9-flat.
2. Remove `react-image-gallery` and `axios` alongside dead-code cleanup (Phase 1).
3. Add `npm audit` (and optionally `npm outdated`) to CI.
4. Add an `engines` field (Node 18+) to `package.json` for reproducible environments.
5. Plan a deliberate major-version upgrade sprint later (React 19 / Vite 6 / Tailwind 4) with tests in place first.
