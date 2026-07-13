import { describe, it, expect } from 'vitest';
import { readFileSync } from 'fs';
import { resolve } from 'path';

const sql = readFileSync(
  resolve(__dirname, '../../../supabase/migrations/019_operations.sql'),
  'utf8',
);

describe('019_operations.sql', () => {
  it('creates admin_audit_logs with RLS', () => {
    expect(sql).toMatch(/CREATE TABLE IF NOT EXISTS public\.admin_audit_logs/);
    expect(sql).toMatch(/ENABLE ROW LEVEL SECURITY/);
    expect(sql).toMatch(/write_admin_audit/);
  });
});
