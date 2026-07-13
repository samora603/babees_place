# Authentication — Technical Reference

Status: Starter content populated during Phase 0 (file previously had a corrupted name and was empty).
Source of truth: `frontend/src/context/AuthContext.jsx`, `frontend/src/components/layout/{ProtectedRoute,AdminRoute}.jsx`, `supabase/migrations/001_schema_rls_place_order.sql`, `supabase/config.toml`.

---

## 1. Mechanism

- Provider: **Supabase Auth** (`@supabase/supabase-js`).
- Active method: **email + password** (`supabase.auth.signInWithPassword`, `supabase.auth.signUp`).
- Session storage: managed by supabase-js (browser `localStorage` by default).
- Global auth state: `AuthContext` (`user`, `profile`, `loading`, `isAuthenticated`, `isAdmin`).

> OTP / phone auth: an `OtpInput` component and an `authService` with `requestOTP`/`verifyOTP` exist but are **not wired into any page** (dead/unused). `authService.js` is additionally **broken** (contains Markdown fences). OTP is therefore *not* a live feature.

## 2. Flow

```
signUp/signIn (AuthContext)
  → Supabase Auth issues JWT + session
  → trigger handle_new_user() creates public.profiles row (role='user')
  → AuthContext.fetchProfile() loads profile
  → onAuthStateChange keeps user/profile in sync
  → post-login effect redirects: admin → /admin/dashboard, else → /shop
```

- Signup passes `full_name` and `phone` via `options.data`; the DB trigger copies them into `profiles`.
- Logout: `supabase.auth.signOut()` then clears context and navigates to `/login`.

## 3. Authorization

- **Roles:** `user`, `admin` (stored in `profiles.role`).
- **Route guards (frontend):**
  - `ProtectedRoute` — requires a logged-in `user`, else redirect `/login`.
  - `AdminRoute` — requires `profile.role === 'admin'`, else redirect `/shop`.
- **Database (authoritative):** RLS policies + `is_admin()` enforce access server-side. Frontend guards are UX only and must never be the sole control.

## 4. Configuration (`supabase/config.toml`)
- `minimum_password_length = 6` (weak — recommend ≥ 8).
- `password_requirements = ""` (no complexity).
- Email `enable_confirmations = false` (users sign in without verifying email).
- `site_url = http://127.0.0.1:3000`, `additional_redirect_urls = ["https://127.0.0.1:3000"]` — **mismatched** with the Vite dev port (5173) and scheme; must be corrected before deploy.
- No CAPTCHA; MFA disabled.

## 5. Known issues (see `docs/03_Security.md`, `docs/audits/SECURITY_AUDIT.md`)
- **CRITICAL:** `profiles_update_own` RLS lacks `WITH CHECK`, allowing a user to set their own `role='admin'` (privilege escalation).
- Weak password policy / no email confirmation.
- No forgot-password flow implemented.
- Dead OTP code (`OtpInput`, `authService`).

## 6. Customer profile data (Phase 2 WS5 — Milestone 5.1)

Beyond `profiles` (identity), customers own:

| Table | Access | Notes |
|---|---|---|
| `customer_addresses` | RLS: `user_id = auth.uid()` | Multi-address book; one default per user |
| `customer_preferences` | RLS: `user_id = auth.uid()` | One row per user; fulfillment + future notification flags |

Frontend services: `addressService`, `customerProfileService`. No service-role key in the browser.

## 7. Conventions (target)
- All privileged mutations validated in-database (RLS / SECURITY DEFINER RPC).
- Never trust frontend role checks alone.
- Role changes should only occur through an admin-only, server-validated path.
