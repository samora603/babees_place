# Security — Engineering Reference

Status: Starter content populated during Phase 0.
Full analysis: `docs/audits/SECURITY_AUDIT.md` and `docs/audits/Security_Baseline.md`.

---

## 1. Security model
- **Authentication:** Supabase Auth (email + password); JWT session managed by `supabase-js`.
- **Authorization:** Postgres **Row Level Security (RLS)** is the authoritative control; the frontend `ProtectedRoute`/`AdminRoute` are UX-only.
- **Roles:** `user`, `admin` (`profiles.role`), evaluated in-DB via `is_admin()`.
- **Secrets:** frontend uses the **public anon key only** (verified `"role":"anon"`). The service-role key must never appear in client code.

> ⚠️ **Live verification (2026-07-12):** a read-only `supabase db dump` of the linked
> project shows the live DB was built manually and does **not** match migration 001.
> The live `profiles` UPDATE policy (`"Users can update their own profile"`) has
> **USING but no `WITH CHECK`** → the role-escalation vulnerability (C-1) is
> **confirmed present on production**. `place_order()`/`is_admin()` do **not** exist
> on live. Migration 002 as written targets the idealized 001 schema and cannot be
> applied as-is. Use the live-compatible fix in `Phase1_Final_Closure_Report.md`.

## 2. RLS (migration 001 = idealized; NOT applied to live)
- Enabled on `profiles`, `cart`, `orders`, `order_items`.
- `cart` owner-only (ALL, with CHECK); `orders` owner/admin select; `order_items` scoped through parent order.
- **Phase 1 (migration `002_phase1_security_hardening.sql`, manual-apply):**
  - `profiles_update_own` now has a `WITH CHECK` that forbids changing `role`; a separate `profiles_update_admin` allows role changes only for existing admins.
  - Direct `INSERT` policies on `orders`/`order_items` were **removed** — order creation is only possible through the `place_order()` RPC, which computes totals server-side.
  - `place_order()` now locks product rows (`FOR UPDATE`) to remove the stock race.

## 3. Open security items (status after Phase 1)
| ID | Severity | Item | Status |
|---|---|---|---|
| C-1 | **Critical** | `profiles` update policy has no `WITH CHECK` → self-escalation | **STILL OPEN ON LIVE.** Client strips `role` (defense-in-depth, done); DB fix authored but 002 doesn't match live — apply the live-compatible SQL in the closure report |
| H-1 | High | Client order fallback + permissive RLS → client-controlled totals | **Fixed**: client fallback removed (`Checkout.jsx` / `orderService`); RLS insert removed in migration 002 (manual apply) |
| H-2 | High | Schema not reproducible → RLS on `products`/`wishlist`/`payments` UNVERIFIED | **Open** — needs `supabase db pull` baseline (manual) |
| H-3 | Med/High | Storage bucket/policies unverified; upload URL bug | **Open** — cannot verify from repo; documented manual review |
| M-2 | Medium | Weak auth config (min length 6, no confirmation, no captcha) | **Open** — `config.toml` change + manual dashboard settings |
| M-1/M-3 | Medium | No input validation; no env-var validation | **Open** — Phase 1+ follow-up |

> Migrations 002/003 are **not auto-applied**. See §7 and the Phase 1 report for the exact manual steps.

## 4. Standing rules (from ADRs / ENGINEERING.md)
- Never disable RLS; every table must have RLS.
- Never commit secrets or the service-role key. `.env` is git-ignored; use `.env.example`.
- Never trust frontend validation or frontend role checks alone.
- Validate ownership before update/delete; least privilege.
- Privileged mutations go through server-validated RPC / Edge Functions.

## 5. Storage
- `products` bucket used by admin uploads; visibility/policies **UNVERIFIED** (not in config/migrations). Must be declared and reviewed before launch.

## 6. Client-side safety
- No `dangerouslySetInnerHTML` found (React auto-escaping mitigates XSS today).
- JWT lives in `localStorage` (standard for supabase-js) — XSS would expose it; keep dependencies patched and avoid injecting untrusted HTML.

## 7. Current security posture
**Score: 4/10 → 6/10 once migrations 002/003 are applied.** The critical (C-1) and high (H-1) findings are now *fixed in code and in versioned migration files*, but the RLS/RPC portions **only take effect after a human applies them to the live database**. Required manual steps (in order):

1. Snapshot/back up the Supabase project.
2. `supabase db pull` to capture the untracked baseline (`products`, `wishlist`, `payments`, storage, etc.).
3. Review then apply `002_phase1_security_hardening.sql` and `003_phase1_indexes_constraints.sql` via the SQL Editor or `supabase db push`.
4. In the Supabase dashboard, harden auth settings (password length/complexity, email confirmation, captcha).

The frontend defense-in-depth changes (client no longer sends `role`; no client-side order path) are already live in the codebase. See `docs/audits/Phase1_Stabilization_Report.md`.
