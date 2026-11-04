import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const viewOnlyPath = path.join(
  process.cwd(),
  "supabase/migrations/20261103140000_free_plan_view_only_enforcement.sql"
)
const transitionsPath = path.join(
  process.cwd(),
  "supabase/migrations/20261103150000_traxpro_free_account_slot_transitions.sql"
)
const copyTradingViewOnlyPath = path.join(
  process.cwd(),
  "supabase/migrations/20261103170000_free_plan_copy_trading_accounts_view_only.sql"
)

describe("free plan view-only enforcement migration", () => {
  it("blocks client can_add_trades updates and extends trade write triggers", () => {
    const sql = fs.readFileSync(viewOnlyPath, "utf8")
    assert.match(sql, /accounts_reject_client_can_add_trades_update/)
    assert.match(sql, /tradetraxs\.mutate_can_add_trades/)
    assert.match(sql, /before update of can_add_trades on public\.accounts/)
    assert.match(sql, /before update on public\.trades/)
    assert.match(sql, /before delete on public\.trades/)
    assert.match(sql, /rate_limit_is_service_role/)
    assert.match(sql, /ACCOUNT_READ_ONLY/)
    assert.match(sql, /select_free_plan_trade_accounts/)
  })

  it("transition migration adds slot epochs and Pro restore RPC", () => {
    const sql = fs.readFileSync(transitionsPath, "utf8")
    assert.match(sql, /free_plan_trade_slots_epoch/)
    assert.match(sql, /free_plan_trade_slots_confirmed_epoch/)
    assert.doesNotMatch(
      sql,
      /grant select \(.*free_plan_trade_slots_epoch/s
    )
    assert.match(sql, /profile_trade_slots_pro/)
    assert.match(sql, /apply_free_plan_trade_slot_downgrade/)
    assert.match(sql, /restore_pro_trade_account_slots/)
    assert.match(sql, /profiles_apply_trade_slot_entitlement_change/)
  })

  it("copy trading migration keeps linked accounts view-only on Free", () => {
    const sql = fs.readFileSync(copyTradingViewOnlyPath, "utf8")
    assert.match(sql, /user_copy_trading_account_ids/)
    assert.match(sql, /enforce_copy_trading_accounts_view_only/)
    assert.match(sql, /COPY_TRADING_ACCOUNT_NOT_ELIGIBLE/)
    assert.match(sql, /apply_free_plan_trade_slot_downgrade/)
    assert.match(sql, /select_free_plan_trade_accounts/)
  })
})
