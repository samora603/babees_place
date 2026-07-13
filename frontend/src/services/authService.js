import { supabase } from '@/lib/supabaseClient';

/**
 * @param {string} email
 * @param {string} password
 */
export async function signInWithPassword(email, password) {
  return supabase.auth.signInWithPassword({ email, password });
}

/**
 * @param {string} email
 * @param {string} password
 * @param {{ fullName?: string, phone?: string }} [metadata]
 */
export async function signUp(email, password, metadata = {}) {
  return supabase.auth.signUp({
    email,
    password,
    options: {
      data: {
        full_name: metadata.fullName || '',
        phone: metadata.phone || '',
      },
    },
  });
}

export async function signOut() {
  return supabase.auth.signOut();
}

export async function getSession() {
  return supabase.auth.getSession();
}

export async function getCurrentUser() {
  return supabase.auth.getUser();
}

/**
 * @param {import('@supabase/supabase-js').SupabaseClient['auth']['onAuthStateChange']} callback
 */
export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange(callback);
}

export const authService = {
  signInWithPassword,
  signUp,
  signOut,
  getSession,
  getCurrentUser,
  onAuthStateChange,
};
