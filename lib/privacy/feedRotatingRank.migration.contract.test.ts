import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { join } from "node:path"

const root = join(import.meta.dirname, "..", "..")

describe("feed rotating rank migrations", () => {
  it("does not modify rpc_v1_feed_bootstrap", () => {
    const sql = readFileSync(
      join(root, "supabase/migrations/20261126003000_rpc_v2_feed_bootstrap.sql"),
      "utf8"
    )
    assert.match(sql, /execute dst;/)
    assert.doesNotMatch(sql, /create or replace function public\.rpc_v1_feed_bootstrap/i)
    assert.match(sql, /rpc_v2_feed_bootstrap/)
    assert.match(sql, /rpc_v1_feed_bootstrap \(4-arg\) was not found/)
    assert.match(sql, /_feed_rotating_v2_install_from_v1/)
    assert.match(sql, /pronargs = 7/)
    assert.match(sql, /FUNCTION\\s\+public\\.rpc_v1_feed_bootstrap/)
    assert.match(sql, /_v2_feed_effective_impressed_at|p_scan_cursor/)
  })

  it("defines impressions + record RPC + select own", () => {
    const sql = readFileSync(
      join(
        root,
        "supabase/migrations/20261126001500_feed_content_impressions.sql"
      ),
      "utf8"
    )
    assert.match(sql, /feed_content_impressions/)
    assert.match(sql, /rpc_v1_feed_record_impressions/)
    assert.match(sql, /enable row level security/)
    assert.match(sql, /feed_content_impressions_select_own/)
    assert.match(sql, /batch_too_large/)
  })

  it("hardening migration purges orphans and rebuilds v2", () => {
    const sql = readFileSync(
      join(
        root,
        "supabase/migrations/20261126010000_feed_rotating_rank_v2_hardening.sql"
      ),
      "utf8"
    )
    assert.match(sql, /feed_impressions_purge_post/)
    assert.match(sql, /_v2_feed_effective_impressed_at/)
    assert.match(sql, /drop function if exists public\.rpc_v2_feed_bootstrap/)
    assert.match(sql, /_feed_rotating_v2_install_from_v1/)
  })
})