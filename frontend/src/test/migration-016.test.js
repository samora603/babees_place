import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(
  __dirname,
  '../../../supabase/migrations/016_payments.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('016_payments.sql', () => {
  it('creates payments and payment_events tables', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.payments/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.payment_events/);
    expect(sql).toMatch(/checkout_request_id/);
    expect(sql).toMatch(/merchant_request_id/);
    expect(sql).toMatch(/receipt_number/);
  });

  it('adds payment_method and mpesa_receipt_number on orders', () => {
    expect(sql).toMatch(/ADD COLUMN IF NOT EXISTS payment_method/);
    expect(sql).toMatch(/ADD COLUMN IF NOT EXISTS mpesa_receipt_number/);
    expect(sql).toMatch(/orders_payment_method_check/);
  });

  it('enables RLS and owner/admin policies', () => {
    expect(sql).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/payments_select_own_or_admin/);
    expect(sql).toMatch(/payment_events_select_own_or_admin/);
  });

  it('extends place_order with payment method default cod', () => {
    expect(sql).toMatch(/p_payment_method text DEFAULT 'cod'/);
  });

  it('creates finalize_payment with duplicate-callback protection', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.finalize_payment/);
    expect(sql).toMatch(/duplicate_callback_ignored/);
    expect(sql).toMatch(/SECURITY DEFINER/);
  });
});
