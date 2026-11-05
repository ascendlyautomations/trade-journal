import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261105133000_trade_room_livekit_phase0.sql"
)

describe("Trade Room live voice Phase 0 migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("adds room_sections.live_kind with check constraint", () => {
    assert.match(sql, /live_kind/)
    assert.match(sql, /voice_open/)
    assert.match(sql, /voice_stage/)
    assert.match(sql, /room_sections_live_kind_check/)
  })

  it("defines disconnect outbox + ban/leave triggers", () => {
    assert.match(sql, /room_livekit_disconnect_outbox/)
    assert.match(sql, /room_bans_livekit_disconnect/)
    assert.match(sql, /room_members_livekit_disconnect/)
    assert.match(sql, /room_livekit_enqueue_disconnect/)
  })

  it("refreshes rpc_v1_room_bootstrap sections payload with live_kind", () => {
    assert.match(sql, /rpc_v1_room_bootstrap/)
    assert.match(sql, /'live_kind', coalesce\(s\.live_kind, 'text'\)/)
  })
})
