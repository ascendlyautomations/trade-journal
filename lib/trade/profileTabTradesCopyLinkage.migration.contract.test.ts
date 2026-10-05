import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261005020000_profile_tab_trades_copy_linkage.sql"
)

describe("Profile tab trades copy linkage migration", () => {
  it("adds profile-only copy linkage helper and merges into profile trades V2", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /trade_summary_profile_copy_linkage_json/)
    assert.match(sql, /rpc_v1_profile_tab_trades_v2/)
    assert.match(sql, /trade_summary_json\(tr, v_viewer\)/)
    assert.match(sql, /trade_summary_profile_copy_linkage_json\(tr\)/)
    assert.match(sql, /'source_account_id'/)
    assert.match(sql, /'copied_account_ids'/)
    assert.match(sql, /'account_id'/)
    assert.match(sql, /copy_traded/)
    assert.match(sql, /and t\.is_public is true/)
    assert.match(sql, /security invoker/)
    assert.doesNotMatch(sql, /'strategy'/)
    assert.doesNotMatch(sql, /'entry_price'/)
    assert.doesNotMatch(sql, /grant select on public\.trades/i)
  })
})
