#!/usr/bin/env node
/**
 * One-time seed for Babees Place auth users.
 *
 * Usage (from repo root):
 *   SUPABASE_URL=https://<ref>.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=<service-role-key> \
 *   node scripts/seed-auth-users.mjs
 *
 * Never commit or expose the service role key in frontend code.
 */
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceRoleKey) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const admin = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const USERS = [
  {
    email: 'admin@babeesplace.com',
    password: 'Admin123!',
    fullName: 'Babees Admin',
    role: 'admin',
  },
  {
    email: 'customer@babeesplace.com',
    password: 'Customer123!',
    fullName: 'Babees Customer',
    role: 'customer',
  },
];

for (const user of USERS) {
  const { data: listed } = await admin.auth.admin.listUsers();
  const existing = listed?.users?.find((u) => u.email === user.email);

  let userId = existing?.id;

  if (!userId) {
    const { data, error } = await admin.auth.admin.createUser({
      email: user.email,
      password: user.password,
      email_confirm: true,
      user_metadata: { full_name: user.fullName, phone: '+254700000000' },
    });
    if (error) {
      console.error(`Failed to create ${user.email}:`, error.message);
      continue;
    }
    userId = data.user.id;
    console.log(`Created auth user ${user.email} (${userId})`);
  } else {
    console.log(`Auth user already exists ${user.email} (${userId})`);
  }

  const { error: profileError } = await admin
    .from('profiles')
    .upsert({
      id: userId,
      email: user.email,
      full_name: user.fullName,
      phone: '+254700000000',
      role: user.role,
    }, { onConflict: 'id' });

  if (profileError) {
    console.error(`Failed to upsert profile for ${user.email}:`, profileError.message);
  } else {
    console.log(`Profile set for ${user.email} with role=${user.role}`);
  }
}

console.log('Done.');
