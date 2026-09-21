import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import { TRADE_SUMMARY_SCHEMA } from "./tradeSummaryV2Contract.ts"

const migrationPath =
  "supabase/migrations/20260927120000_trade_summary_owner_journal_list_v2.sql"

describe("Phase 8D owner journal list migration", () => {
  const sql = readFileSync(migrationPath, "utf8")

  it("defines V2 RPC without replacing V1 bootstrap", () => {
    assert.match(sql, /rpc_v1_trades_list_bootstrap_v2/)
    assert.doesNotMatch(sql, /create or replace function public\.rpc_v1_trades_list_bootstrap\(/)
  })

  it("uses canonical summary schema and owner extension builder", () => {
    assert.match(sql, /trade_summary_owner_journal_json/)
    assert.match(sql, /trade_summary_json\(p_trade, p_viewer_id\)/)
    assert.match(sql, /trade_summary_json\(p_trade, p_viewer_id\)/)
  })

  it("owner extension includes journal list fields only", () => {
    for (const key of [
      "account_id",
      "account_name",
      "strategy",
      "entry_price",
      "exit_price",
      "session",
    ]) {
      assert.match(sql, new RegExp(`'${key}'`))
    }
    const ownerExt =
      sql.match(
        /create or replace function public\.trade_summary_owner_extension_json[\s\S]*?\$\$;/,
      )?.[0] ?? ""
    assert.doesNotMatch(ownerExt, /psychology_notes/)
    assert.doesNotMatch(ownerExt, /import_fingerprint/)
  })

  it("returns contract_version v2", () => {
    assert.match(sql, /'contract_version', 'v2'/)
  })
})
