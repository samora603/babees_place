import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(__dirname, '../../../supabase/migrations/013_order_fulfillment.sql');
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('013_order_fulfillment.sql', () => {
  it('creates pickup_locations table', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.pickup_locations/);
    expect(sql).toMatch(/is_active boolean NOT NULL DEFAULT true/);
  });

  it('adds order fulfillment columns', () => {
    expect(sql).toMatch(/delivery_type text/);
    expect(sql).toMatch(/pickup_location_id uuid/);
    expect(sql).toMatch(/delivery_address jsonb/);
    expect(sql).toMatch(/delivery_fee numeric/);
    expect(sql).toMatch(/customer_note text/);
  });

  it('extends order status check with confirmed and ready_for_pickup', () => {
    expect(sql).toMatch(/confirmed/);
    expect(sql).toMatch(/ready_for_pickup/);
    expect(sql).toMatch(/VALIDATE CONSTRAINT orders_status_check/);
  });

  it('creates order_events table for notification hooks', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.order_events/);
    expect(sql).toMatch(/log_order_event/);
  });

  it('extends place_order with fulfillment parameters', () => {
    expect(sql).toMatch(/p_delivery_type text/);
    expect(sql).toMatch(/p_pickup_location_id uuid/);
    expect(sql).toMatch(/p_delivery_address jsonb/);
  });

  it('creates update_order_status RPC', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.update_order_status/);
    expect(sql).toMatch(/Use cancel_order\(\) to cancel orders/);
  });

  it('creates update_order_payment_status RPC', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.update_order_payment_status/);
  });

  it('hardens cancel_order for customer vs admin', () => {
    expect(sql).toMatch(/NOT v_is_admin AND v_order\.status NOT IN \('pending', 'confirmed'\)/);
  });
});
