import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

describe("trades_select_shared_in_trade_room migration", () => {
  it("scopes private room trade reads to members", () => {
    const sql = readFileSync(
      new URL(
        "../../supabase/migrations/20261124230000_trades_select_shared_in_trade_room.sql",
        import.meta.url
      ),
      "utf8"
    )
    assert.match(sql, /trades_select_shared_in_trade_room/)
    assert.match(sql, /room_messages/)
    assert.match(sql, /is_active_room_member/)
    assert.doesNotMatch(sql, /is_public\s*=\s*true/i)
  })
})