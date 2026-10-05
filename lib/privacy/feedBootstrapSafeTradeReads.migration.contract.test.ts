import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const migrationPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../supabase/migrations/20261005140000_feed_bootstrap_safe_trade_reads.sql"
)

describe("feed bootstrap safe trade reads", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("uses definer helper for feed trade payload reads", () => {
    assert.match(sql, /_v1_feed_post_trade_payload[\s\S]*security definer/i)
    assert.match(sql, /profile_viewer_can_view_trades/)
    assert.match(sql, /viewer_has_block_with/)
    assert.match(sql, /profile_is_visible_to_viewer/)
  })

  it("keeps feed bootstrap invoker and removes direct trades joins", () => {
    assert.match(sql, /rpc_v1_feed_bootstrap must stay security invoker/)
    assert.match(sql, /left join public\.trades t on t\.id = p\.trade_id/)
    assert.match(sql, /_v1_feed_post_trade_payload\(p\.trade_id, tr, v_guest\)/)
    assert.match(sql, /trades_public_read tx/)
  })

  it("does not restore table select or expose journal columns", () => {
    assert.doesNotMatch(sql, /grant select on table public\.trades/i)
    assert.doesNotMatch(sql, /disable row level security/i)
    assert.doesNotMatch(sql, /'notes'/)
    assert.doesNotMatch(sql, /\bnotes\b/)
  })
})
