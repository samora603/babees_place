# Changelog

This changelog reflects the **actual** state of the repository. The previous
version listed aspirational releases (up to a "v1.0.0 Production Release") that
had not occurred; it was corrected during Phase 0. The project is **pre-MVP**.

Format: reverse chronological. Versioning follows [SemVer]; the project has not
yet reached a tagged release.

---

## [Unreleased]

### Phase 0 — Foundation & Audit Closure
- Repaired root `.gitignore` (was an empty directory → now a proper ignore file).
- Added `frontend/.gitignore`.
- Untracked `frontend/.env` and added `frontend/.env.example` (anon-key-only; no secrets committed).
- Fixed corrupted documentation filename (`04_Authentication.md` had a literal newline).
- Populated previously empty engineering/technical docs with accurate, evidence-based content.
- Synchronized README / ENGINEERING with the real repository structure.
- Produced Phase 0 audit set under `docs/audits/` and `docs/architecture/`.

### Initial engineering audit
- Produced comprehensive audits (`docs/audits/PROJECT_AUDIT.md` and companions) and `docs/NEXT_STEPS.md`.

## History
- Initial commit: project scaffold — frontend (React+Vite), Supabase migration `001`, docs skeleton.

---

> Estimated overall completion at time of writing: ~45–50% (see `docs/audits/PROJECT_AUDIT.md`).
> Prior aspirational entries (v0.1–v1.0) were removed as inaccurate.
