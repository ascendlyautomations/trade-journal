import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import test from "node:test"

const root = path.resolve(import.meta.dirname, "..")

test("admin_historical_engagement_bundle migration contract", () => {
  const sql = readFileSync(
    path.join(root, "supabase/migrations/20261123210000_admin_historical_engagement_bundle_filters.sql"),
    "utf8"
  )
  assert.match(sql, /create or replace function public\.admin_historical_engagement_bundle/)
  assert.match(sql, /p_start_date date/)
  assert.match(sql, /p_activity_filter/)
  assert.match(sql, /admin_historical_engagement_had_content_action/)
  assert.match(sql, /tradesByExecutionDatePerDay/)
  assert.match(sql, /is_initial_import/)
  assert.match(sql, /grant execute on function public\.admin_historical_engagement_bundle\(int, date, date, text\) to authenticated/)
  assert.doesNotMatch(sql, /product_events/)
  assert.doesNotMatch(sql, /insert into public\.product_events/)
})