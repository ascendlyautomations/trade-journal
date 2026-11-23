import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import test from "node:test"

const root = path.join(import.meta.dirname, "..")

test("admin_lifecycle_analytics_bundle migration contract", () => {
  const sql = readFileSync(
    path.join(root, "supabase/migrations/20261123230100_admin_lifecycle_analytics_bundle.sql"),
    "utf8"
  )
  assert.match(sql, /create or replace function public\.admin_lifecycle_analytics_bundle/)
  assert.match(sql, /grant execute on function public\.admin_lifecycle_analytics_bundle\(int, date, date\) to authenticated/)
  assert.match(sql, /userGrowthActivation/)
  assert.match(sql, /traxsProConversion/)
  assert.match(sql, /retentionChurn/)
})