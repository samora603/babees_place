import { describe, it, expect, beforeEach } from 'vitest';
import { logger } from '@/services/logger';
import { toCsv } from '@/services/exportService';
import { validateClientEnv, createRateLimiter } from '@/utils/envValidation';
import { previewCheckoutRewards } from '@/services/rewardEngine';

describe('logger', () => {
  beforeEach(() => {
    logger.clear();
    logger.setLevel('debug');
  });

  it('records structured entries and redacts secrets', () => {
    logger.info('app', 'hello', { token: 'super-secret-value-here', ok: true });
    const recent = logger.getRecentLogs();
    expect(recent.at(-1).message).toBe('hello');
    expect(recent.at(-1).meta.token).toBe('[REDACTED]');
    expect(recent.at(-1).meta.ok).toBe(true);
  });
});

describe('exportService', () => {
  it('builds CSV with escaping', () => {
    const csv = toCsv([{ name: 'A,B', qty: 1 }], ['name', 'qty']);
    expect(csv).toContain('"A,B"');
    expect(csv.split('\n')[0]).toBe('name,qty');
  });
});

describe('envValidation', () => {
  it('requires supabase public env', () => {
    const bad = validateClientEnv({});
    expect(bad.ok).toBe(false);
    expect(bad.missing).toContain('VITE_SUPABASE_URL');

    const good = validateClientEnv({
      VITE_SUPABASE_URL: 'https://x.supabase.co',
      VITE_SUPABASE_ANON_KEY: 'anon-key',
    });
    expect(good.ok).toBe(true);
  });

  it('rate limiter enforces window', () => {
    const limiter = createRateLimiter({ max: 2, windowMs: 60_000 });
    expect(limiter.allow()).toBe(true);
    expect(limiter.allow()).toBe(true);
    expect(limiter.allow()).toBe(false);
  });
});

describe('production readiness smoke', () => {
  it('reward engine still works for checkout totals', () => {
    const preview = previewCheckoutRewards({
      lines: [{ id: '1', productId: 'p', price: 1000, quantity: 1 }],
      deliveryType: 'pickup',
    });
    expect(preview.total).toBe(1000);
  });
});
