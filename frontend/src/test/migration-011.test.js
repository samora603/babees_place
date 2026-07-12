import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(__dirname, '../../../supabase/migrations/011_inventory_hardening.sql');
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('011_inventory_hardening.sql', () => {
  it('adds non-negative stock CHECK constraint', () => {
    expect(sql).toMatch(/products_stock_nonneg_check/);
    expect(sql).toMatch(/CHECK \(stock >= 0\)/);
    expect(sql).toMatch(/VALIDATE CONSTRAINT products_stock_nonneg_check/);
  });

  it('updates place_order to reject inactive products', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.place_order/);
    expect(sql).toMatch(/p\.is_active/);
    expect(sql).toMatch(/is no longer available/);
  });

  it('creates cancel_order RPC with stock restore', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.cancel_order/);
    expect(sql).toMatch(/stock = p\.stock \+ oi\.quantity/);
    expect(sql).toMatch(/status = 'cancelled'/);
    expect(sql).toMatch(/REVOKE ALL ON FUNCTION public\.cancel_order/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.cancel_order/);
  });

  it('makes cancel_order idempotent for already cancelled orders', () => {
    expect(sql).toMatch(/IF v_order\.status = 'cancelled' THEN/);
    expect(sql).toMatch(/RETURN;/);
  });
});
