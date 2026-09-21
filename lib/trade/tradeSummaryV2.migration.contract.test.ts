import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260926150000_trade_summary_v2_profile_tab.sql"
)

describe("Phase 8B migration contract", () => {
  it("defines TradeSummary helpers and profile tab V2 without touching V1", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /trade_summary_json/)
    assert.match(sql, /trade_summary_note_preview/)
    assert.match(sql, /trade_summary_v1/)
    assert.match(sql, /rpc_v1_profile_tab_trades_v2/)
    assert.match(sql, /rpc_v1_profile_tab_trades_summary_shadow_compare/)
    assert.match(sql, /security invoker/)
    assert.match(sql, /grant execute on function public\.rpc_v1_profile_tab_trades_v2/)
    assert.match(sql, /grant execute on function public\.rpc_v1_profile_tab_trades_v2\(uuid, integer, text\) to anon/)
    assert.doesNotMatch(sql, /create or replace function public\.rpc_v1_profile_tab_trades\(/)
    assert.doesNotMatch(sql, /rpc_v1_trades_list_bootstrap/)
    assert.doesNotMatch(sql, /rpc_v1_trade_detail_bootstrap/)
    assert.doesNotMatch(sql, /rpc_v1_analytics_dashboard_bootstrap_v3/)
  })

  it("does not expose account_id on canonical summary json", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    const summaryFn = sql.split("create or replace function public.trade_summary_json")[1]?.split(
      "create or replace function public.trade_summary_owner_extension_json"
    )[0]
    assert.ok(summaryFn)
    assert.doesNotMatch(summaryFn!, /'account_id'/)
    assert.doesNotMatch(summaryFn!, /'account_name'/)
    assert.match(sql, /trade_summary_owner_extension_json/)
  })
})
