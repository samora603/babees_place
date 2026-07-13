-- =============================================================================
-- Babees Place — Seed auth users (profiles + admin role promotion)
-- =============================================================================
-- IMPORTANT: auth.users rows CANNOT be created reliably with plain INSERT
-- from the SQL editor because passwords must be bcrypt-hashed by Supabase Auth.
--
-- Create the auth users FIRST using ONE of:
--   A) Supabase Dashboard → Authentication → Users → Add user
--   B) Sign up via the app / Register page
--   C) One-time script with service role (scripts/seed-auth-users.mjs)
--
-- Then run THIS file in Supabase SQL Editor to ensure profiles + admin role.
-- =============================================================================

BEGIN;

-- Ensure signup trigger exists (migration 003)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Upsert profile rows for known seed accounts (safe if trigger already ran)
INSERT INTO public.profiles (id, email, full_name, phone, role)
SELECT
  u.id,
  u.email,
  COALESCE(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
  COALESCE(u.raw_user_meta_data->>'phone', ''),
  CASE
    WHEN u.email = 'admin@babeesplace.com' THEN 'admin'
    ELSE 'customer'
  END
FROM auth.users u
WHERE u.email IN ('admin@babeesplace.com', 'customer@babeesplace.com')
ON CONFLICT (id) DO UPDATE
SET
  email = EXCLUDED.email,
  full_name = COALESCE(public.profiles.full_name, EXCLUDED.full_name),
  role = CASE
    WHEN EXCLUDED.email = 'admin@babeesplace.com' THEN 'admin'
    ELSE public.profiles.role
  END;

-- Force admin role for the admin account
UPDATE public.profiles
SET role = 'admin'
WHERE email = 'admin@babeesplace.com';

-- Force customer role for the customer account
UPDATE public.profiles
SET role = 'customer'
WHERE email = 'customer@babeesplace.com';

COMMIT;

-- Verify
SELECT id, email, role, full_name
FROM public.profiles
WHERE email IN ('admin@babeesplace.com', 'customer@babeesplace.com');
