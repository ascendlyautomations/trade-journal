import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import test from "node:test"

const root = path.resolve(import.meta.dirname, "..")

test("admin product analytics phase 2 migration defines bundle RPC", () => {
  const sql = readFileSync(
    path.join(root, "supabase/migrations/20261123143000_admin_product_analytics_bundle_phase2.sql"),
    "utf8"
  )
  assert.match(sql, /create or replace function public\.admin_product_analytics_bundle/)
  assert.match(sql, /grant execute on function public\.admin_product_analytics_bundle\(int\) to authenticated/)
  assert.match(sql, /admin_users/)
  assert.match(sql, /product_daily_user_activity/)
})

test("admin product analytics audit fixes migration", () => {
  const sql = readFileSync(
    path.join(root, "supabase/migrations/20261123160000_admin_product_analytics_bundle_audit_fixes.sql"),
    "utf8"
  )
  assert.match(sql, /product_daily_feature_user_day/)
  assert.match(sql, /manualEntered/)
  assert.match(sql, /d1MatureCohortSize/)
})