import assert from "node:assert/strict"
import { test } from "node:test"
import { buildTradeRoomBroadcastLiveNotifyContent } from "./tradeRoomBroadcastLiveNotifyContent.ts"
import { summarizeGeneralVoicePresence } from "./tradeRoomGeneralVoicePresence.ts"
import { TrackSource } from "livekit-server-sdk"

test("buildTradeRoomBroadcastLiveNotifyContent includes collapse id", () => {
  const content = buildTradeRoomBroadcastLiveNotifyContent({
    roomId: "room-1",
    roomSlug: "momentum",
    roomName: "Momentum Traders",
    broadcastSessionId: "sess-abc",
  })
  assert.equal(content.room_slug, "momentum")
  assert.equal(content.collapse_id, "room-live:sess-abc")
})

test("summarizeGeneralVoicePresence counts unmuted microphones", () => {
  const summary = summarizeGeneralVoicePresence([
    {
      tracks: [{ source: TrackSource.MICROPHONE, muted: false }],
    },
    {
      tracks: [{ source: TrackSource.MICROPHONE, muted: true }],
    },
    { tracks: [] },
  ])
  assert.equal(summary.connectedCount, 3)
  assert.equal(summary.speakingCount, 1)
})
