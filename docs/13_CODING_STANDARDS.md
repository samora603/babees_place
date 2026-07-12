# Coding Standards

## General

Write readable code.

Avoid shortcuts.

Avoid duplicated code.

Keep functions small.

Keep components focused.

---

## Naming

PascalCase

Components

camelCase

Functions

UPPER_CASE

Environment variables

---

## React

Prefer functional components.

Use hooks.

Avoid prop drilling.

Keep components under roughly 250 lines when practical.

---

## Security

Never trust frontend validation.

Validate all user input.

Never expose secrets.

Never bypass RLS.

---

## Tooling (current status — updated in Phase 1)

The quality toolchain is now configured in `frontend/`:

- **ESLint** — `.eslintrc.cjs` (ESLint 8 legacy config) with `eslint:recommended`,
  `plugin:react`, and `plugin:react-hooks`. Run `npm run lint`; it passes with 0
  errors (some non-blocking `no-unused-vars` warnings remain and are tracked).
  `.eslintignore` excludes `dist/`, `node_modules/`, and test artifacts.
- **Prettier** — `.prettierrc.json` (single quotes, 100 col, 2-space). Run
  `npm run format` (write) or `npm run format:check`.
- **EditorConfig** — root `.editorconfig` (UTF-8, LF, 2-space).
- **Husky + lint-staged** — a pre-commit hook lives at `.husky/pre-commit` and runs
  `lint-staged` (config in `frontend/package.json`). Because the npm package lives
  in `frontend/` while the git root is the repository root, enable the hook once with:
  `git config core.hooksPath .husky` (the agent intentionally did not modify git config).

"No lint errors" in the Definition of Done is now enforceable and is checked in CI
(`.github/workflows/ci.yml`).

## Git

Commit often.

Small commits.

Clear messages.

Never commit:

node_modules

dist

.env

These are enforced by the root `.gitignore` and `frontend/.gitignore` (repaired in Phase 0).
