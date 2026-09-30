import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260930163000_trades_authenticated_journal_privacy.sql"
)

describe("trades authenticated journal privacy migration", () => {
  it("revokes authenticated table select and grants only social-safe columns", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /revoke select on table public\.trades from authenticated/)
    const grantSection =
      sql.match(
        /grant select \([\s\S]*?\) on table public\.trades to authenticated/
      )?.[0] ?? ""
    assert.match(grantSection, /grant select \(/)
    assert.doesNotMatch(grantSection, /\bnotes\b/)
    assert.doesNotMatch(grantSection, /psychology_notes/)
    assert.doesNotMatch(grantSection, /\baccount_id\b/)
  })

  it("adds owner-only SECURITY DEFINER read RPCs bound to auth.uid()", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /create or replace function public\.rpc_v1_trade_owner_read/)
    assert.match(sql, /create or replace function public\.rpc_v1_trades_owner_rows/)
    assert.match(sql, /security definer/)
    assert.match(sql, /t\.user_id = auth\.uid\(\)/)
    assert.match(sql, /set search_path = public, pg_temp/)
    assert.doesNotMatch(sql, /security definer view/i)
  })

  it("promotes owner bootstrap RPCs to SECURITY DEFINER", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /alter function public\.rpc_v1_trades_list_bootstrap_v2/)
    assert.match(sql, /alter function public\.rpc_v1_dashboard_bootstrap/)
  })
})
