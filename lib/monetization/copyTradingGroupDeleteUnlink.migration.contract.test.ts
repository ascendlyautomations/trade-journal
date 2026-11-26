import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261126160000_copy_trading_group_delete_unlink.sql"
)

describe("copy trading group delete unlink (20261126160000)", () => {
  it("allows metadata-only copy_trading_group_id unlink on update", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /create or replace function public\.trades_enforce_account_can_add_trades\(\)/)
    assert.match(sql, /tg_op = 'UPDATE'/)
    assert.match(sql, /old\.copy_trading_group_id is not null/)
    assert.match(sql, /new\.copy_trading_group_id is null/)
    assert.match(
      sql,
      /\(to_jsonb\(old\) - 'copy_trading_group_id'\)\s*=\s*\(to_jsonb\(new\) - 'copy_trading_group_id'\)/
    )
  })

  it("preserves ownership and free-slot enforcement after unlink guard", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /ACCOUNT_OWNERSHIP_MISMATCH/)
    assert.match(sql, /ACCOUNT_READ_ONLY/)
    assert.match(sql, /ACCOUNT_SLOT_SELECTION_REQUIRED/)
    assert.match(sql, /profile_trade_slots_pro_for_user/)
    assert.doesNotMatch(sql, /delete from public\.trades/)
    assert.doesNotMatch(sql, /drop trigger/)
  })
})