import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const migrationPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../supabase/migrations/20261001161722_feed_viewer_sync_safe_trade_reads.sql"
)

describe("feed and viewer sync trade column grant fix", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("keeps feed invoker and stops passing a whole trades row", () => {
    assert.match(sql, /pg_get_functiondef omits SECURITY INVOKER/)
    assert.match(sql, /rpc_v1_feed_bootstrap must stay security invoker/)
    assert.match(sql, /_v1_feed_post_trade_payload\(p\.trade_id, tr, v_guest\)/)
    assert.match(sql, /left join public\.trades t on t\.id = p\.trade_id/)
    assert.match(sql, /security invoker/)
    assert.match(sql, /drop function if exists public\._v1_feed_post_trade_payload\(public\.trades, public\.reels, boolean\)/)
  })

  it("makes owner-scoped sync and journal RPCs security definer", () => {
    assert.match(sql, /alter function public\.rpc_v1_viewer_sync_state\(\) security definer/i)
    assert.match(sql, /alter function public\.rpc_v1_calendar_bootstrap\(integer, integer, uuid, timestamp with time zone, timestamp with time zone\) security definer/i)
    assert.match(sql, /alter function public\.rpc_v1_trade_detail_owner_comparison\(text\) security definer/i)
    assert.match(sql, /and t\.user_id = v_uid/)
  })

  it("does not restore table select or disable RLS", () => {
    assert.doesNotMatch(sql, /grant select on table public\.trades/i)
    assert.doesNotMatch(sql, /disable row level security/i)
    assert.doesNotMatch(sql, /select[\s\S]*\bnotes\b/)
    assert.doesNotMatch(sql, /t\.account_id/)
  })
})
