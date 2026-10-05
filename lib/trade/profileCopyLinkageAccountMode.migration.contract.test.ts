import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261005030000_profile_copy_linkage_account_mode.sql"
)

describe("Profile copy linkage account_mode migration", () => {
  it("adds participating account mode to profile copy linkage JSON", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /trade_summary_profile_copy_linkage_json/)
    assert.match(sql, /'account_mode'/)
    assert.match(sql, /trade_summary_profile_participating_account_mode/)
    assert.match(sql, /analytics_trade_account_uuid/)
    assert.match(sql, /profile_statistics_resolve_account_mode/)
    const helperIdx = sql.indexOf(
      "trade_summary_profile_participating_account_mode"
    )
    const linkageIdx = sql.indexOf("trade_summary_profile_copy_linkage_json")
    assert.ok(helperIdx >= 0 && linkageIdx >= 0 && helperIdx < linkageIdx)
  })
})
