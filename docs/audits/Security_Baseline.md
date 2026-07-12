# Phase 0 — Security Baseline

Auditor: Security Engineer
Date: 2026-07-12
Scope: repository-level security review (code + config + Git). Not a live pentest.
Cross-reference: `docs/audits/SECURITY_AUDIT.md` (full analysis), `docs/03_Security.md`.

---

## Baseline score: 4/10 → 5/10
Phase 0 resolved the Git-hygiene/secrets exposure items (raising the baseline), but the **critical privilege-escalation flaw and order-integrity flaw remain OPEN** (code/DB changes deferred per Phase 0 rules).

---

## 1. Checklist results

| Check | Result | Evidence |
|---|---|---|
| Exposed secrets | ✅ None private | Only public anon key was committed; now untracked (Environment Audit) |
| Hardcoded credentials | ✅ None | `grep` of `src/` clean |
| Service-role usage in client | ✅ None | Only `VITE_SUPABASE_ANON_KEY` (role `anon`) used |
| Dangerous client-side authorization | ⚠️ Guards are UX-only | `ProtectedRoute`/`AdminRoute` acceptable **iff** RLS is authoritative |
| Disabled-RLS assumptions | ⚠️ Partial | Core tables have RLS; 6 tables UNVERIFIED |
| Unsafe localStorage usage | ⚠️ Standard | supabase-js stores JWT in localStorage (default); no extra sensitive data stored by app |
| XSS risks | ✅ Low | No `dangerouslySetInnerHTML`; React auto-escapes |
| Insecure API calls | ⚠️ Yes | Client-side order fallback allows client-controlled totals/prices |
| Privilege escalation | ❌ **Critical** | `profiles_update_own` RLS lacks `WITH CHECK` → user can self-set `role='admin'` |

## 2. Findings (repository-level)

### CRITICAL — OPEN
- **SB-1. Role self-escalation.** `profiles_update_own` (`001_...sql:132-134`) has `USING (auth.uid()=id)` but no `WITH CHECK` and no column restriction. Any user can `update({role:'admin'})` their own row. Defeats all authorization. *Fix in Phase 1 (DB change).*

### HIGH — OPEN
- **SB-2. Order integrity.** Checkout fallback `createOrderFromCart` + permissive `orders_insert_own`/`order_items_insert_own` let the client set `total_amount`, `price`, `name`. Prices/totals are not trustworthy. *Fix: remove fallback; server-only totals.*
- **SB-3. Unverified RLS / irreproducible schema.** `products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses` are not in migrations; their RLS cannot be confirmed. *Fix: `supabase db pull` + verify RLS.*

### MEDIUM — OPEN
- **SB-4. Weak auth config.** min password length 6, no complexity, no email confirmation, no captcha (`config.toml`).
- **SB-5. No input validation / no env validation.**
- **SB-6. Storage policies unverified**; `getPublicUrl` bug.

### RESOLVED in Phase 0
- **SB-7.** `.env` committed → untracked + ignored; `.env.example` added.
- **SB-8.** Root `.gitignore` was a directory → real file (prevents future secret/artifact commits).
- **SB-9.** Confirmed committed key is public anon (not service-role).

## 3. OWASP snapshot
- A01 Broken Access Control — **Failing** (SB-1, SB-2).
- A05 Security Misconfiguration — **Improved** (Git hygiene fixed); auth config still weak (SB-4).
- A08 Data Integrity — **Failing** (SB-2).
- A09 Logging/Monitoring — **Failing** (none).
- A03 Injection / A07 Auth — Low/Partial (parameterized queries; weak password policy).

## 4. Client-side authorization guidance
Frontend route guards are acceptable **only** as UX. The security boundary must be RLS + server-validated RPC/Edge Functions. Today that boundary is broken by SB-1/SB-2. Do not treat `AdminRoute` as a real control.

## 5. Phase 1 security priorities
1. Fix SB-1 (role escalation) — **blocker**.
2. Fix SB-2 (order integrity).
3. `supabase db pull` + verify RLS everywhere (SB-3).
4. Harden auth config (SB-4).
5. Add input + env validation (SB-5); verify storage policies + fix upload bug (SB-6).
6. Add monitoring/logging (A09).
7. Optional: rotate anon key + scrub history.
