# Phase 0 — Environment Audit

Auditor: DevOps / Security Engineer
Date: 2026-07-12
Scope: environment-variable usage, secret exposure, `.env` handling.

---

## 1. Environment variables in use
Only two, both consumed in `frontend/src/lib/supabaseClient.js`:
| Variable | Purpose | Sensitivity |
|---|---|---|
| `VITE_SUPABASE_URL` | Supabase project URL | Public |
| `VITE_SUPABASE_ANON_KEY` | Supabase **anon** key | Public (safe for browser) |

`grep` for `import.meta.env` shows no other env usage. No backend env (no server).

## 2. Secret exposure review
- **Committed `.env`:** `frontend/.env` was tracked in Git. Its contents are only the URL + anon key.
- **Anon key verification:** decoded the JWT payload → `{"iss":"supabase","ref":"qfcygrxrfszcdltangec","role":"anon"}`. It is the **public anon key**, **not** a service-role key. So no privileged secret was exposed.
- **Service-role / private keys:** none found anywhere in the repo (`grep` for `service_role`, `SUPABASE_SERVICE`, `secret_key`, `BEGIN PRIVATE/RSA` returned only doc/config comments and vendor skill docs).
- **Hardcoded credentials:** none found in `src/`.

## 3. Actions taken in Phase 0
| Action | Status |
|---|---|
| Untrack `frontend/.env` (`git rm --cached`, file kept on disk) | ✅ Done |
| Add root `.gitignore` ignoring `.env`, `.env.*` (except `.env.example`) | ✅ Done |
| Add `frontend/.gitignore` (same rules) | ✅ Done |
| Add `frontend/.env.example` (documented keys, no values) | ✅ Done |
| Verify `git check-ignore frontend/.env` passes | ✅ Done |
| Verify `.env` no longer in `git ls-files` | ✅ Done |

> Note: the anon key value still exists in **Git history** (prior commit). Because it is a public key this is low-risk, but if desired the history can be rewritten and the key rotated in the Supabase dashboard. Rotation was **not** performed (requires project access + is optional for a public key).

## 4. `.env.example`
Created at `frontend/.env.example`:
```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```
with comments emphasizing anon-key-only and "never commit the real `.env`".

## 5. Environment separation
- ❌ No dev/staging/prod separation exists. A single Supabase project is referenced.
- **Recommendation:** separate Supabase projects (or at least separate keys) per environment; inject `VITE_*` via host build secrets; never point previews at prod data.

## 6. `config.toml` secret handling (backend)
- Good pattern: secrets referenced via `env(...)` substitution (Twilio, SMTP, S3, OpenAI) rather than inline. ✅
- ⚠️ `openai_api_key = "env(OPENAI_API_KEY)"` etc. are placeholders; ensure real values are only provided via environment, never committed.

## 7. Verdict
- No private secrets are (or were) committed; the only committed key is the public anon key.
- Env hygiene is now correct going forward (`.env` ignored + `.env.example` present).
- Remaining: optional key rotation/history scrub, and real environment separation for deployment.

**Environment hygiene score: 3/10 → 8/10** (after Phase 0 fixes).
