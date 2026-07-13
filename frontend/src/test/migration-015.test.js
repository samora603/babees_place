import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(
  __dirname,
  '../../../supabase/migrations/015_recommendations.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('015_recommendations.sql', () => {
  it('creates get_bestseller_product_ids SECURITY DEFINER function', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.get_bestseller_product_ids/);
    expect(sql).toMatch(/SECURITY DEFINER/);
    expect(sql).toMatch(/SET search_path = public/);
  });

  it('grants execute to anon and authenticated', () => {
    expect(sql).toMatch(/GRANT EXECUTE ON FUNCTION public\.get_bestseller_product_ids\(integer\) TO anon, authenticated/);
  });

  it('excludes cancelled orders and inactive products', () => {
    expect(sql).toMatch(/o\.status IS DISTINCT FROM 'cancelled'/);
    expect(sql).toMatch(/p\.is_active IS TRUE/);
  });
});
