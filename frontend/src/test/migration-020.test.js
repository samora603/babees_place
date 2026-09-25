import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const sql = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/020_security_hardening.sql'),
  'utf8',
);

describe('020_security_hardening.sql', () => {
  it('creates server-side promotion computation helper', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.compute_checkout_promotions/);
    expect(sql).toMatch(/status = 'active'/);
    expect(sql).toMatch(/REVOKE ALL ON FUNCTION public\.compute_checkout_promotions/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.compute_checkout_promotions/);
  });

  it('hardens place_order to ignore client discount inputs', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.place_order\(/);
    expect(sql).toMatch(/NOT trusted for pricing decisions/);
    expect(sql).toMatch(/compute_checkout_promotions\(p_user_id\)/);
    expect(sql).toMatch(/v_coupon\.discount_type = 'percentage'/);
    expect(sql).toMatch(/client_discount_ignored/);
    expect(sql).not.toMatch(/v_discount numeric\(12,2\) := GREATEST\(COALESCE\(p_discount_amount/);
  });

  it('requires payment ownership or admin for finalize_payment', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.finalize_payment\(/);
    expect(sql).toMatch(/auth\.uid\(\) IS DISTINCT FROM v_payment\.user_id AND NOT public\.is_admin\(\)/);
  });

  it('requires order ownership or admin for award_loyalty_for_order', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.award_loyalty_for_order\(/);
    expect(sql).toMatch(/auth\.uid\(\) IS DISTINCT FROM v_order\.user_id AND NOT public\.is_admin\(\)/);
  });

  it('restricts direct customer payment UPDATE to admin only', () => {
    expect(sql).toMatch(/DROP POLICY IF EXISTS payments_update_own_or_admin/);
    expect(sql).toMatch(/CREATE POLICY payments_update_admin_only/);
    expect(sql).toMatch(/USING \(public\.is_admin\(\)\)/);
  });

  it('blocks direct admin order UPDATE bypass and guards sensitive columns', () => {
    expect(sql).toMatch(/DROP POLICY IF EXISTS "Admins can update orders"/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.guard_orders_direct_update/);
    expect(sql).toMatch(/CREATE TRIGGER orders_guard_sensitive_update/);
    expect(sql).toMatch(/Direct order updates to status, payment, or financial fields are not allowed/);
  });

  it('preserves authenticated grants on hardened RPCs', () => {
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.place_order\(/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.finalize_payment\(/);
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.award_loyalty_for_order\(/);
  });
});

describe('020 security attack scenarios (static contract)', () => {
  it('place_order computes coupon percentage from database row', () => {
    expect(sql).toMatch(/round\(v_subtotal \* COALESCE\(v_coupon\.percent_off, 0\) \/ 100\.0, 2\)/);
  });

  it('place_order computes coupon fixed amount from database row', () => {
    expect(sql).toMatch(/v_coupon_discount := COALESCE\(v_coupon\.amount_off, 0\)/);
  });

  it('place_order enforces loyalty max redeem percent server-side', () => {
    expect(sql).toMatch(/max_redeem_percent/);
    expect(sql).toMatch(/v_points_value := LEAST\(v_points_value, v_max_loyalty, v_remaining\)/);
  });

  it('finalize_payment rejects unauthenticated callers', () => {
    expect(sql).toMatch(/IF auth\.uid\(\) IS NULL THEN\s+RAISE EXCEPTION 'Not authenticated'/s);
  });

  it('award_loyalty_for_order rejects unauthenticated callers', () => {
    const fn = sql.match(
      /CREATE OR REPLACE FUNCTION public\.award_loyalty_for_order[\s\S]*?END;\s*\$\$/i,
    )?.[0];
    expect(fn).toMatch(/IF auth\.uid\(\) IS NULL THEN/);
    expect(fn).toMatch(/Unauthorized/);
  });
});
