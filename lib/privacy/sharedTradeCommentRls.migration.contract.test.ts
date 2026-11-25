import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

describe("trades_select_shared_in_comment migration", () => {
  it("scopes private comment trade reads to visible comment rows", () => {
    const sql = readFileSync(
      new URL(
        "../../supabase/migrations/20261124250000_trades_select_shared_in_comment.sql",
        import.meta.url
      ),
      "utf8"
    )
    assert.match(sql, /trades_select_shared_in_comment/)
    assert.match(sql, /shared_trade_id/)
    assert.match(sql, /comments_assert_shared_trade_owned/)
    assert.match(sql, /trade_comments/)
    assert.match(sql, /profile_post_comments/)
    assert.doesNotMatch(sql, /is_public\s*=\s*true/i)
  })
})