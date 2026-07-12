import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(__dirname, '../../../supabase/migrations/012_product_management.sql');
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('012_product_management.sql', () => {
  it('reconciles products.updated_at in migration chain', () => {
    expect(sql).toMatch(/ADD COLUMN IF NOT EXISTS updated_at timestamptz/);
  });

  it('backfills product slugs from name', () => {
    expect(sql).toMatch(/UPDATE public\.products/);
    expect(sql).toMatch(/SET slug = lower/);
  });

  it('creates unique slug indexes', () => {
    expect(sql).toMatch(/idx_products_slug_unique/);
    expect(sql).toMatch(/idx_categories_slug_unique/);
    expect(sql).toMatch(/UNIQUE INDEX/);
  });

  it('adds price validation CHECK constraints', () => {
    expect(sql).toMatch(/products_price_nonneg_check/);
    expect(sql).toMatch(/products_discount_lte_price_check/);
    expect(sql).toMatch(/VALIDATE CONSTRAINT products_price_nonneg_check/);
    expect(sql).toMatch(/VALIDATE CONSTRAINT products_discount_lte_price_check/);
  });
});
