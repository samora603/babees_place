import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(__dirname, '../../../supabase/migrations/014_customer_profile.sql');
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('014_customer_profile.sql', () => {
  it('creates customer_addresses table with required columns', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.customer_addresses/);
    expect(sql).toMatch(/recipient_name text NOT NULL/);
    expect(sql).toMatch(/street_address text NOT NULL/);
    expect(sql).toMatch(/is_default boolean NOT NULL DEFAULT false/);
    expect(sql).toMatch(/customer_addresses_label_check/);
  });

  it('creates customer_preferences table', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.customer_preferences/);
    expect(sql).toMatch(/preferred_fulfillment text/);
    expect(sql).toMatch(/preferred_pickup_location_id uuid REFERENCES public\.pickup_locations/);
    expect(sql).toMatch(/marketing_emails boolean NOT NULL DEFAULT false/);
    expect(sql).toMatch(/sms_notifications boolean NOT NULL DEFAULT false/);
  });

  it('enables RLS on both tables', () => {
    expect(sql).toMatch(/ALTER TABLE public\.customer_addresses ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/ALTER TABLE public\.customer_preferences ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/customer_addresses_select_own/);
    expect(sql).toMatch(/customer_preferences_select_own/);
    expect(sql).toMatch(/user_id = auth\.uid\(\)/);
  });

  it('enforces single default address via trigger', () => {
    expect(sql).toMatch(/enforce_single_default_address/);
    expect(sql).toMatch(/customer_addresses_single_default/);
  });

  it('uses set_updated_at triggers', () => {
    expect(sql).toMatch(/customer_addresses_set_updated_at/);
    expect(sql).toMatch(/customer_preferences_set_updated_at/);
  });
});
