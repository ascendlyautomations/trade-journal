import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

const sql = readFileSync(
  "supabase/migrations/20261124130000_traxpro_premium_server_enforcement.sql",
  "utf8"
)

describe("traxpro premium server enforcement migration", () => {
  it("defines shared assert helper and gates premium RPCs", () => {
    assert.match(sql, /create or replace function public\.traxpro_assert_feature_access/)
    assert.match(sql, /rpc_v1_analytics_dashboard_aggregate_charts_v3/)
    assert.match(sql, /rpc_v1_analytics_dashboard_account_charts_v3/)
    assert.match(sql, /traxpro_assert_feature_access\(v_uid, 'premium_analytics'\)/)
    assert.match(sql, /rpc_v1_prop_firm_bootstrap/)
    assert.match(sql, /traxpro_assert_feature_access\(v_uid, 'prop_firm'\)/)
  })

  it("extends copy trading and expense tracker mutation enforcement", () => {
    assert.match(sql, /copy_trading_group_accounts_enforce_traxpro/)
    assert.match(sql, /before insert or update or delete on public\.copy_trading_groups/)
    assert.match(sql, /prop_firm_expenses_enforce_traxpro/)
    assert.match(sql, /tracker_income_enforce_traxpro/)
  })
})