import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const migrationPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../supabase/migrations/20261001174213_dashboard_analytics_owner_trade_reads.sql"
)

describe("dashboard analytics owner trade reads", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("owner-checks and defines the chart helpers that scan trades", () => {
    for (const name of [
      "analytics_dashboard_equity_block",
      "analytics_dashboard_distributions_block",
      "analytics_dashboard_insights_block",
      "analytics_dashboard_streak_snapshot",
    ]) {
      assert.match(sql, new RegExp(name))
    }
    assert.match(sql, /auth\.uid\(\) is not distinct from p_user_id/)
    assert.match(sql, /security definer/)
    assert.match(sql, /grant execute on function public\.%I\(uuid, date, date, uuid\) to authenticated/)
  })

  it("does not restore table select or disable RLS", () => {
    assert.doesNotMatch(sql, /grant select on table public\.trades/i)
    assert.doesNotMatch(sql, /disable row level security/i)
  })
})
