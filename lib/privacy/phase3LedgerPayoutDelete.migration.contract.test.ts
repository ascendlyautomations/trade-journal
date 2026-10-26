import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261026180000_phase3_ledger_payout_delete_atomic.sql"
)

describe("phase 3 ledger payout delete migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("defines atomic delete_account_payout_entry RPC", () => {
    assert.match(sql, /delete_account_payout_entry/)
    assert.match(sql, /security definer/)
    assert.match(sql, /delete from public\.account_payout_entries/)
    assert.match(sql, /delete from public\.achievements/)
  })

  it("links achievements only by metadata.account_payout_entry_id", () => {
    assert.match(
      sql,
      /metadata->>'account_payout_entry_id' = p_entry_id::text/
    )
    assert.doesNotMatch(sql, /value_numeric/)
    assert.doesNotMatch(sql, /payout_date/)
    assert.doesNotMatch(sql, /interval/)
  })

  it("enforces owner-only delete and idempotent missing entry", () => {
    assert.match(sql, /v_owner_id is distinct from v_user_id/)
    assert.match(sql, /if not found then/)
    assert.match(sql, /for update/)
  })
})

describe("phase 3 ledger payout delete clients", () => {
  it("web and iOS call the same RPC without client-side heuristics", () => {
    const web = fs.readFileSync(
      path.join(process.cwd(), "lib/accountPayoutEntry.ts"),
      "utf8"
    )
    const ios = fs.readFileSync(
      path.join(
        process.cwd(),
        "native-ios/TradeTraxs/TradeTraxs/Data/Repositories/DefaultTradeRepository.swift"
      ),
      "utf8"
    )
    assert.match(web, /rpc\("delete_account_payout_entry"/)
    assert.doesNotMatch(web, /deletePayoutAchievementsForLedgerEntry/)
    assert.doesNotMatch(web, /value_numeric/)
    assert.match(ios, /delete_account_payout_entry/)
    assert.doesNotMatch(ios, /deleteLinkedLedgerPayoutAchievements/)
    assert.doesNotMatch(ios, /value_numeric \?\? 0\) - amount/)
  })

  it("preserves separate prop cycle delete_prop_payout RPC", () => {
    const webProp = fs.readFileSync(
      path.join(process.cwd(), "lib/propfirmPayoutCycles.ts"),
      "utf8"
    )
    assert.match(webProp, /rpc\("delete_prop_payout"/)
    assert.doesNotMatch(webProp, /delete_account_payout_entry/)
    const phase2 = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20261026140000_phase2_trading_data_integrity.sql"
      ),
      "utf8"
    )
    assert.match(phase2, /account_payout_cycle_id/)
  })
})
