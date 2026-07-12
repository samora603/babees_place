# Security Audit — Babees Place

Auditor role: Security Engineer
Date: 2026-07-12
Method: Evidence-based static review of the repository (`frontend/`, `supabase/`, `docs/`).
Scope note: The live Supabase project (`project-ref: qfcygrxrfszcdltangec`) was **not** accessed. Any statement about the *remote* database, buckets, or policies that are **not** present in `supabase/migrations/` is explicitly flagged as **UNVERIFIED**.

---

## Security Score: 4 / 10

The application demonstrates good security *intent* (RLS enabled on core tables, an atomic `SECURITY DEFINER` checkout RPC, anon-key-only frontend client). However, it contains at least one **critical privilege-escalation flaw**, commits its `.env` file, has a non-functional root `.gitignore`, and a large part of the database schema is not reproducible from migrations, so most policies cannot be verified.

---

## 1. Critical findings

### C-1. Privilege escalation via `profiles` UPDATE policy (CRITICAL)
Evidence — `supabase/migrations/001_schema_rls_place_order.sql:132-134`:

```sql
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE USING (auth.uid() = id);
```

- The policy has a `USING` clause but **no `WITH CHECK`** and **no column restriction**.
- `profiles.role` (`'user' | 'admin'`) lives in the same row the user is allowed to update.
- Any authenticated user can therefore run
  `supabase.from('profiles').update({ role: 'admin' }).eq('id', <ownId>)`
  and promote themselves to admin. The frontend even forwards arbitrary fields:
  `AuthContext.updateProfile` (`frontend/src/context/AuthContext.jsx:92-116`) and
  `userService.updateProfile` (`frontend/src/services/userService.js:8-25`) both spread `...rest` into the update.
- Admin authorization (`AdminRoute`, `is_admin()`, `orders_update_admin`) all key off `profiles.role`, so this single flaw defeats the entire authorization model.

**Fix:** restrict the column set and add a `WITH CHECK` that forbids role changes, e.g. move `role` out of user-writable columns or add a trigger/policy such as:
```sql
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id AND role = (SELECT role FROM public.profiles WHERE id = auth.uid()));
```
(or revoke `UPDATE(role)` from `authenticated` and only mutate role through a `SECURITY DEFINER` admin RPC).

### C-2. `.env` committed to Git (HIGH)
Evidence — `git ls-files` returns `frontend/.env`; `git show HEAD:frontend/.env` returns the real `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
- The anon key is publicly shippable by design, so this is not an immediate compromise, **but**:
  - It normalizes committing secret files. The moment a service-role key, SMTP, or M-Pesa credential is added to `.env`, it will be leaked in history.
  - There is **no `.env.example`**; onboarding relies on the committed real file.
- Compounded by **C-3**.

### C-3. Root `.gitignore` is a directory, not a file (HIGH)
Evidence — `ls -la .gitignore/` shows `.gitignore` is an (empty) **directory**; `git ls-files .gitignore/` returns nothing.
- There is effectively **no repository-level ignore policy**. `node_modules/` and `dist/` happen to be untracked today (confirmed via `git ls-files`), but nothing prevents a future `git add .` from committing build output, local env files, or secrets.
- `frontend/` has **no `.gitignore` of its own** either.

---

## 2. High / Medium findings

### H-1. Client-side order integrity bypass (HIGH)
- The correct path is `place_order` (`SECURITY DEFINER`), which computes totals and validates stock **server-side** (`001_...sql:171-237`). Good.
- But `Checkout.jsx:34-42` falls back to `orderService.createOrderFromCart` (`orderService.js:67-129`) on any RPC error. That fallback inserts `orders` and `order_items` **directly from the client**, and the RLS policies permit it:
  - `orders_insert_own` only checks `user_id = auth.uid()` — the client controls `total_amount`.
  - `order_items_insert_own` only checks order ownership — the client controls `price`, `name`, `quantity`.
- A malicious user can trigger the fallback (or call the tables directly) to create an order with an arbitrary low total / arbitrary prices. **Order and payment totals are not trustworthy.**
- **Fix:** remove the client-side fallback, make `total_amount`/`order_items.price` server-computed only (deny direct inserts, force all order creation through the RPC).

### H-2. Database schema not reproducible; most RLS UNVERIFIED (HIGH)
- `supabase/migrations/20260617042152_remote_schema.sql` is **0 bytes** (empty).
- Migration `001` only defines `profiles`, `orders`, `order_items`, `cart`.
- Tables the code depends on but that are **absent from migrations**: `products`, `categories`, `wishlist`, `payments`, `pickup_locations`, `addresses`, and any `settings` table.
- Therefore RLS status for `products`, `wishlist`, `payments`, `pickup_locations`, `addresses`, etc. **cannot be verified** and may be missing entirely. Per the project's own ADR-006 ("every application table must use RLS"), this is a standards violation and a real exposure risk until proven otherwise.

### H-3. Storage buckets & policies UNVERIFIED (MEDIUM/HIGH)
- `adminService.uploadImages` writes to a `products` storage bucket (`adminService.js:200-217`), but no bucket is declared in `supabase/config.toml` (the `[storage.buckets.*]` blocks are commented out) and none exist in migrations.
- Bucket visibility (public/private) and object RLS **cannot be verified**.
- Bug: `getPublicUrl` is destructured as `{ publicURL }` (`adminService.js:210`); supabase-js v2 returns `{ data: { publicUrl } }`, so uploaded URLs are `undefined` — indicates the upload path is untested.

### M-1. No output sanitization / XSS posture (MEDIUM)
- No use of `dangerouslySetInnerHTML` was found (good — React escapes by default), so stored-XSS risk is low **today**.
- However there is **no input validation layer** (no schema validation such as Zod/Yup). Inputs are passed straight to Supabase. Product `name`, profile fields, notes, etc. are unvalidated on the client and (given H-2) possibly unconstrained in the DB.

### M-2. Auth hardening gaps (MEDIUM)
- `supabase/config.toml`: `minimum_password_length = 6`, `password_requirements = ""` (no complexity), `enable_confirmations = false` for email (users sign in without verifying email). For a production commerce app these should be raised (length ≥ 8, enable email confirmation, consider captcha — `[auth.captcha]` is disabled).
- No CAPTCHA / bot protection on signup or login.
- JWT handling is delegated to `supabase-js` (localStorage session) — standard; acceptable but note tokens live in `localStorage` (XSS would expose them).

### M-3. No environment validation (MEDIUM)
- `frontend/src/lib/supabaseClient.js` calls `createClient(url, key)` with no guard. If envs are missing the client is created with `undefined`, failing silently at runtime with confusing errors.

---

## 3. Low findings / observations

- **L-1.** 28 `console.*` statements across `src/` leak internal errors/objects to the browser console in production (`grep -rn "console\." src | wc -l` = 28).
- **L-2.** `frontend/src/services/authService.js` contains **literal Markdown code fences (```` ``` ````) inside a `.js` file** (lines 7, 17, 24, 38, 60, 72) — it is not valid JavaScript. It is currently unused (not imported anywhere) so it does not break the build, but it is dead, broken code that should be removed or fixed.
- **L-2b.** `place_order` iterates the cart to check stock but does **not** lock product rows (`FOR UPDATE`), so concurrent checkouts can oversell inventory (race condition).
- **L-3.** No rate limiting beyond Supabase defaults is configured for custom flows; acceptable at this stage.
- **L-4.** No CSRF concern for the SPA (token-based auth, no cookie session) — informational only.

---

## 4. Dependency review
- Dependencies are recent (`@supabase/supabase-js ^2.78`, `react ^18.2`, `react-router-dom ^6.20`, `vite ^5`).
- `npm install` reported deprecation warnings only (eslint@8, glob@7, rimraf@3, inflight) — no install-time vulnerability output was captured; a formal `npm audit` was **not run** and should be part of CI.
- `axios ^1.6` is a dependency but the only axios file (`services/api.js`) is unused/dead — remove to shrink the attack surface.

---

## 5. OWASP quick map
| Risk | Status |
|---|---|
| A01 Broken Access Control | **Failing** — C-1 privilege escalation, H-1 order integrity |
| A02 Cryptographic Failures | N/A (Supabase-managed) / anon key public by design |
| A03 Injection | Low (parameterized supabase-js; no raw SQL from client) |
| A04 Insecure Design | Partial — client-side order fallback (H-1) |
| A05 Security Misconfiguration | **Failing** — `.env` committed, broken root `.gitignore`, weak auth config |
| A06 Vulnerable Components | Unverified — no `npm audit` in CI |
| A07 Auth Failures | Partial — weak password policy, no email confirmation |
| A08 Data Integrity | **Failing** — client-controlled totals/prices (H-1) |
| A09 Logging/Monitoring | **Failing** — none configured |
| A10 SSRF | N/A |

---

## 6. Prioritized remediation
1. **C-1** Lock down `profiles` role updates (privilege escalation). *Blocker for any launch.*
2. **H-1** Remove client-side order creation; enforce server-computed totals/prices.
3. **C-2 / C-3** Replace directory `.gitignore` with a real ignore file, add `frontend/.gitignore`, remove `frontend/.env` from tracking (`git rm --cached`), add `.env.example`, rotate the key if any private key was ever committed.
4. **H-2** Commit the full schema to migrations; prove RLS on every table.
5. **H-3** Declare/verify storage buckets and object policies; fix `getPublicUrl` usage.
6. **M-2** Harden auth config (password length/complexity, email confirmation, captcha).
7. **M-1/M-3** Add input validation and env-var validation.
8. **L-1/L-2** Remove `console.*` noise and the broken `authService.js`.
