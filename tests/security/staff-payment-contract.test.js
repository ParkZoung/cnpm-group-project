const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const migration = readFileSync(join(
  'backend', 'supabase', 'migrations', '20260805000100_staff_payments_lifecycle.sql'
), 'utf8');
const branchSessionMigration = readFileSync(join(
  'backend', 'supabase', 'migrations', '20260805000300_staff_branch_sessions_and_immediate_online_checkin.sql'
), 'utf8');
const staffDashboard = readFileSync(join('frontend', 'js', 'staff-dashboard.js'), 'utf8');

describe('staff/payment migration contract', () => {
  test('lets active staff select a working branch instead of assigning one permanently', () => {
    assert.match(branchSessionMigration, /CREATE TABLE public\.staff_work_sessions/);
    assert.match(branchSessionMigration, /staff_select_working_branch/);
    assert.match(branchSessionMigration, /UPDATE public\.profiles SET branch_id = NULL WHERE role = 'staff'/);
  });

  test('calculates the deposit from authoritative nightly price and tax', () => {
    assert.match(migration, /b\.price_per_night::numeric \* \(100 \+ b\.tax_rate\) \/ 100/);
    assert.match(migration, /b\.number_of_nights = 1 AND p_payment_option <> 'full'/);
  });

  test('enforces payment gates for check-in and check-out', () => {
    assert.match(migration, /b\.paid_amount\s*<\s*b\.upfront_amount/);
    assert.match(migration, /o\.status<>'approved'/);
    assert.match(migration, /SET status='consumed'/);
    assert.match(migration, /b\.booking_status <> 'checked_in' OR b\.paid_amount <> b\.total_amount/);
  });

  test('does not credit a customer payment claim before staff approval', () => {
    assert.match(migration, /SET status='payment_claimed'/);
    assert.match(migration, /staff_review_online_payment/);
    assert.doesNotMatch(migration, /simulate_online_payment/);
  });

  test('scopes staff booking management through the selected working branch', () => {
    assert.match(branchSessionMigration, /JOIN public\.staff_work_sessions s ON s\.staff_id = p\.id/);
    assert.match(branchSessionMigration, /s\.branch_id = p_branch_id/);
    assert.match(branchSessionMigration, /public\.is_staff_for_branch\(r\.branch_id\)/);
  });

  test('opens online check-in immediately after confirmation', () => {
    assert.match(branchSessionMigration, /b\.booking_status <> 'confirmed'/);
    assert.doesNotMatch(branchSessionMigration, /b\.check_in_date - 1/);
  });

  test('removes the complete QR prefix without truncating the UUID', () => {
    assert.match(staffDashboard, /const prefix = 'gostay:checkin:'/);
    assert.match(staffDashboard, /raw\.slice\(prefix\.length\)/);
    assert.doesNotMatch(staffDashboard, /raw\.slice\(16\)/);
  });

  test('shows the guest-facing room number instead of the internal room id', () => {
    assert.match(staffDashboard, /roomDisplayName\(booking && booking\.room, row\.room_id\)/);
    assert.match(staffDashboard, /room\.room_number/);
    assert.doesNotMatch(staffDashboard, /Phòng #\$\{escapeHtml\(row\.room_id\)\}/);
  });

  test('disables arrival confirmation outside the booked stay dates', () => {
    assert.match(staffDashboard, /today < booking\.check_in_date/);
    assert.match(staffDashboard, /today >= booking\.check_out_date/);
    assert.match(staffDashboard, /canConfirmArrival \? '' : ' disabled'/);
    assert.match(staffDashboard, /if \(!canConfirmArrival\) return/);
  });
});
