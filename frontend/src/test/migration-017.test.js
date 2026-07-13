import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const MIGRATION_PATH = resolve(
  __dirname,
  '../../../supabase/migrations/017_notifications.sql',
);
const sql = readFileSync(MIGRATION_PATH, 'utf8');

describe('017_notifications.sql', () => {
  it('creates core notification tables', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.notifications/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.notification_templates/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.notification_deliveries/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.notification_preferences/);
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.notification_events/);
  });

  it('enables RLS and policies', () => {
    expect(sql).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/notifications_select_own_or_admin/);
    expect(sql).toMatch(/notification_preferences_select_own/);
  });

  it('creates helpers for read / admin fan-out', () => {
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.notify_admin_users/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.mark_notification_read/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.mark_all_notifications_read/);
    expect(sql).toMatch(/CREATE OR REPLACE FUNCTION public\.ensure_notification_preferences/);
  });

  it('extends customer_preferences notification flags', () => {
    expect(sql).toMatch(/email_notifications/);
    expect(sql).toMatch(/order_updates/);
    expect(sql).toMatch(/payment_updates/);
  });

  it('seeds templates including payment and admin events', () => {
    expect(sql).toMatch(/payment_successful/);
    expect(sql).toMatch(/admin_new_order/);
    expect(sql).toMatch(/admin_low_inventory/);
  });
});
