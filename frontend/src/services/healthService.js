import { supabase } from '@/lib/supabaseClient';
import { getPaymentProvider } from '@/services/providers/paymentProvider';
import { getEmailProvider, getSmsProvider } from '@/services/providers/notificationProviderFactory';
import { errorReportingService } from '@/services/errorReportingService';
import { logger } from '@/services/logger';
import { APP_VERSION, APP_NAME } from '@/constants/version';

/**
 * System health probes for admin operations dashboard.
 */

async function probeDatabase() {
  const started = performance.now();
  try {
    const { error } = await supabase.from('profiles').select('id', { count: 'exact', head: true }).limit(1);
    const ms = Math.round(performance.now() - started);
    if (error) return { ok: false, latencyMs: ms, detail: error.message };
    return { ok: true, latencyMs: ms, detail: 'Reachable' };
  } catch (err) {
    return { ok: false, latencyMs: null, detail: err.message || 'Unreachable' };
  }
}

async function probeStorage() {
  const started = performance.now();
  try {
    const { data, error } = await supabase.storage.listBuckets();
    const ms = Math.round(performance.now() - started);
    if (error) return { ok: false, latencyMs: ms, detail: error.message };
    const names = (data || []).map((b) => b.name);
    return {
      ok: true,
      latencyMs: ms,
      detail: names.length ? `Buckets: ${names.join(', ')}` : 'No buckets listed',
    };
  } catch (err) {
    return { ok: false, latencyMs: null, detail: err.message || 'Unreachable' };
  }
}

function probeEnv() {
  const url = Boolean(import.meta.env.VITE_SUPABASE_URL);
  const anon = Boolean(import.meta.env.VITE_SUPABASE_ANON_KEY);
  const missing = [];
  if (!url) missing.push('VITE_SUPABASE_URL');
  if (!anon) missing.push('VITE_SUPABASE_ANON_KEY');
  return {
    ok: missing.length === 0,
    detail: missing.length ? `Missing: ${missing.join(', ')}` : 'Core env present',
    mode: import.meta.env.MODE,
    paymentProvider: import.meta.env.VITE_PAYMENT_PROVIDER || 'mock',
    emailProvider: import.meta.env.VITE_EMAIL_PROVIDER || 'mock',
    smsProvider: import.meta.env.VITE_SMS_PROVIDER || 'mock',
    errorProvider: errorReportingService.getProviderId(),
    logLevel: logger.getLevel(),
  };
}

function probeProviders() {
  let payment;
  let email;
  let sms;
  try {
    payment = getPaymentProvider();
  } catch (err) {
    payment = { id: 'error', error: err.message };
  }
  try {
    email = getEmailProvider();
  } catch (err) {
    email = { id: 'error', error: err.message };
  }
  try {
    sms = getSmsProvider();
  } catch (err) {
    sms = { id: 'error', error: err.message };
  }
  return {
    payment: { id: payment.id, ok: payment.id !== 'error', detail: payment.error || 'Loaded' },
    email: { id: email.id, ok: email.id !== 'error', detail: email.error || 'Loaded' },
    sms: { id: sms.id, ok: sms.id !== 'error', detail: sms.error || 'Loaded' },
  };
}

/**
 * Migration status is informational — live project may not have recorded history.
 */
async function probeMigrations() {
  const expected = [
    '001', '002', '003', '004', '005', '006', '007', '008', '009', '010',
    '011', '012', '013', '014', '015', '016', '017', '018', '019',
  ];
  return {
    ok: true,
    expectedCount: expected.length,
    latestAuthored: '019_operations.sql',
    detail: 'Authored locally through 019. Apply on linked Supabase before production cutover.',
    note: 'Live migration history may still be empty — see Migration_History.md',
  };
}

export async function getSystemHealth() {
  const [database, storage] = await Promise.all([probeDatabase(), probeStorage()]);
  const env = probeEnv();
  const providers = probeProviders();
  const migrations = await probeMigrations();

  const checks = { database, storage, env, providers, migrations };
  const criticalOk = database.ok && env.ok;

  return {
    status: criticalOk ? (storage.ok ? 'healthy' : 'degraded') : 'unhealthy',
    checkedAt: new Date().toISOString(),
    version: APP_VERSION,
    appName: APP_NAME,
    checks,
  };
}

export const healthService = {
  getSystemHealth,
  probeDatabase,
  probeStorage,
  probeEnv,
};
