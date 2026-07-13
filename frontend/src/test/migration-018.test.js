import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(
  __dirname,
  '../../../supabase/migrations/018_promotions_loyalty.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('018_promotions_loyalty.sql', () => {
  it('creates core reward tables', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.promotions/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.coupons/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.loyalty_accounts/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.gift_cards/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.referrals/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.reward_events/);
  });

  it('extends place_order with reward params', () => {
    expect(sql).toMatch(/p_coupon_code/);
    expect(sql).toMatch(/p_loyalty_points/);
    expect(sql).toMatch(/p_gift_card_code/);
    expect(sql).toMatch(/p_discount_amount/);
    expect(sql).toMatch(/DROP FUNCTION IF EXISTS public\.place_order/);
  });

  it('enables RLS', () => {
    expect(sql).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/promotions_select_active_or_admin/);
    expect(sql).toMatch(/loyalty_accounts_select_own_or_admin/);
  });

  it('seeds mock coupons and loyalty rules', () => {
    expect(sql).toMatch(/WELCOME15/);
    expect(sql).toMatch(/GIFT1000/);
    expect(sql).toMatch(/loyalty_rules/);
  });
});
