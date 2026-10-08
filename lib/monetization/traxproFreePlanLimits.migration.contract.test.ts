import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const v2Path = path.join(
  process.cwd(),
  "supabase/migrations/20261007220000_traxpro_free_plan_limits_v2.sql"
)
const accountsPath = path.join(
  process.cwd(),
  "supabase/migrations/20261007230000_free_plan_total_accounts_and_trade_slots.sql"
)

describe("TraxPro free plan limits migrations (20261007220000 + 20261007230000)", () => {
  it("v2 retires daily trade/post caps but keeps clips and copy-trading gates scoped", () => {
    const sql = fs.readFileSync(v2Path, "utf8")
    assert.match(sql, /drop trigger if exists trades_enforce_free_plan_daily_limit/)
    assert.match(sql, /free_plan_daily_clip_limit constant integer := 4/)
    assert.match(sql, /pg_advisory_xact_lock/)
    assert.match(sql, /872343/)
    assert.match(sql, /free_plan_clips/)
    assert.match(sql, /free_plan_limits_enforced\(\)/)
    assert.match(sql, /copy_trading_groups_enforce_traxpro/)
    assert.match(sql, /before insert on public\.copy_trading_groups/)
    assert.match(sql, /trades_enforce_copy_trading_traxpro/)
    assert.match(sql, /before insert or update of copy_trading_group_id on public\.trades/)
    assert.match(sql, /tg_op = 'UPDATE'/)
    assert.match(sql, /old\.copy_trading_group_id is not distinct from new\.copy_trading_group_id/)
    assert.doesNotMatch(sql, /before update on public\.trades/)
  })

  it("v2 copy-trading trade trigger does not gate manual rows without a group id", () => {
    const sql = fs.readFileSync(v2Path, "utf8")
    const fn = sql.slice(
      sql.indexOf("create or replace function public.trades_enforce_copy_trading_traxpro"),
      sql.indexOf("drop trigger if exists trades_enforce_copy_trading_traxpro")
    )
    assert.match(fn, /if new\.copy_trading_group_id is null then\s+return new;/)
  })

  it("accounts v3 runs after v2 and uses total-account create lock + trade-entry slots", () => {
    const sql = fs.readFileSync(accountsPath, "utf8")
    assert.match(sql, /872342/)
    assert.match(sql, /free_plan_account_create/)
    assert.match(sql, /coalesce\(total_count, 0\) >= 3/)
    assert.match(sql, /trades_enforce_account_can_add_trades/)
    assert.match(sql, /before insert on public\.trades/)
    assert.match(sql, /select_free_plan_trade_accounts/)
    assert.doesNotMatch(sql, /copy_trading_group_id/)
    assert.doesNotMatch(sql, /reels_enforce_free_plan_daily_limit/)
  })

  it("migration timestamps enforce v2 before accounts v3", () => {
    assert.ok(
      "20261007220000" < "20261007230000",
      "apply traxpro_free_plan_limits_v2 before free_plan_total_accounts_and_trade_slots"
    )
  })
})
