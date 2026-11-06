import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

const baseSql = readFileSync(
  "supabase/migrations/20261105193000_trade_room_live_broadcast.sql",
  "utf8"
)
const voiceModeSql = readFileSync(
  "supabase/migrations/20261105210000_trade_room_broadcast_voice_mode.sql",
  "utf8"
)

describe("Trade Room live broadcast migration contract", () => {
  it("defines room_live_broadcasts with one active row per room", () => {
    assert.match(baseSql, /room_live_broadcasts/)
    assert.match(baseSql, /room_live_broadcasts_one_active_per_room_idx/)
    assert.match(baseSql, /enable row level security/)
    assert.match(baseSql, /ended_at is null/)
  })

  it("adds voice_mode and video_source session metadata", () => {
    assert.match(voiceModeSql, /voice_mode/)
    assert.match(voiceModeSql, /broadcast_only/)
    assert.match(voiceModeSql, /open_voice/)
    assert.match(voiceModeSql, /video_source/)
  })
})
