const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migration = readFileSync(join(
  'backend', 'supabase', 'migrations', '20260805000500_admin_profiles_with_email.sql'
), 'utf8');

test('admin profile email RPC is admin-only and joins Auth by profile ID', () => {
  assert.match(migration, /IF NOT public\.is_admin\(\)/);
  assert.match(migration, /JOIN auth\.users AS auth_user ON auth_user\.id = profile\.id/);
  assert.match(migration, /SECURITY DEFINER/);
  assert.match(migration, /SET search_path = ''/);
  assert.match(migration, /REVOKE EXECUTE .* FROM PUBLIC, anon/);
});
