import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const migration = readFileSync(
  "supabase/migrations/20260716220000_early_access_pro_for_life.sql",
  "utf8"
)

test("claim RPC is service-only and serializes campaign claims", () => {
  assert.match(migration, /create or replace function public\.claim_pro_for_life/)
  assert.match(migration, /pg_advisory_xact_lock/)
  assert.match(
    migration,
    /grant execute on function public\.claim_pro_for_life\(uuid, text\) to service_role/
  )
  assert.doesNotMatch(
    migration,
    /grant execute on function public\.claim_pro_for_life\(uuid, text\) to authenticated/
  )
})

test("award ledger has a unique user and environment-specific cap configuration", () => {
  assert.match(
    migration,
    /user_id uuid primary key references public\.profiles/
  )
  assert.match(
    migration,
    /\('traxs_pro_for_life_v1', 'production', true, 100, 1\)/
  )
  assert.match(
    migration,
    /\('traxs_pro_for_life_v1', 'preview', true, 110, 1\)/
  )
  assert.match(
    migration,
    /\('traxs_pro_for_life_v1', 'development', true, 110, 1\)/
  )
})

test("public trade qualification uses immutable server-authored publication time", () => {
  assert.match(migration, /new\.first_published_at := now\(\)/)
  assert.match(
    migration,
    /new\.first_published_at := old\.first_published_at/
  )
  assert.match(
    migration,
    /timezone\('America\/New_York', t\.first_published_at\)::date/
  )
})

test("temporary access and permanent access remain independent from Stripe", () => {
  assert.match(
    migration,
    /p\.early_access_status = 'active'[\s\S]*p\.early_access_ends_at > now\(\)/
  )
  assert.match(
    migration,
    /new\.is_pro := true;[\s\S]*new\.lifetime_access_source := old\.lifetime_access_source/
  )
  assert.doesNotMatch(migration, /insert into public\.subscriptions/)
})

test("migration leaves all existing profiles unenrolled", () => {
  const schemaSetup = migration.slice(
    0,
    migration.indexOf("drop function if exists public.enroll_early_access")
  )
  assert.match(
    migration,
    /add column if not exists early_access_enrolled_at timestamptz/
  )
  assert.match(
    migration,
    /add column if not exists early_access_started_at timestamptz/
  )
  assert.doesNotMatch(schemaSetup, /update public\.profiles/)
  assert.doesNotMatch(schemaSetup, /insert into public\.pro_for_life_awards/)
})

test("enrollment requires an eligible new standard signup", () => {
  assert.match(
    migration,
    /p_enrollment_source not in \('standard_email', 'standard_oauth'\)/
  )
  assert.match(
    migration,
    /profile_row\.created_at < campaign\.eligibility_starts_at/
  )
  assert.match(
    migration,
    /profile_row\.signup_flow_source is not null[\s\S]*profile_row\.signup_flow_source is distinct from p_enrollment_source/
  )
  assert.match(migration, /interval '21 days'/)
  assert.match(migration, /coalesce\(profile_row\.is_pro, false\)/)
  assert.match(migration, /coalesce\(profile_row\.creator_access, false\)/)
  assert.match(migration, /coalesce\(profile_row\.is_beta_tester, false\)/)
  assert.match(migration, /profile_row\.stripe_customer_id is not null/)
  assert.match(migration, /profile_row\.trial_end is not null/)
  assert.match(
    migration,
    /profile_row\.lifetime_access_source is not null/
  )
  assert.match(
    migration,
    /grant execute on function public\.enroll_early_access\(uuid, text, text\) to service_role/
  )
})
