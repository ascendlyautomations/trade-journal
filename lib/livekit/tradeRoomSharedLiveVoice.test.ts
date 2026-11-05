import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  liveKitRoomName,
  parseLegacySectionLiveKitRoomName,
  parseLiveKitRoomName,
} from "./liveKitRoomName.ts"
import {
  normalizeTradeRoomLiveVoiceKind,
  tradeRoomSupportsSharedLiveVoice,
  TRADE_ROOM_GENERAL_VOICE_LABEL,
} from "./tradeRoomSharedLiveVoice.ts"

describe("Trade Room shared live voice identity", () => {
  it("uses tt/{roomId}/voice for LiveKit room names", () => {
    const roomId = "11111111-1111-1111-1111-111111111111"
    assert.equal(
      liveKitRoomName(roomId),
      `tt/${roomId}/voice`
    )
    assert.deepEqual(parseLiveKitRoomName(`tt/${roomId}/voice`), { roomId })
    assert.equal(parseLiveKitRoomName(`tt/${roomId}/other`), null)
  })

  it("still parses legacy section-scoped names for disconnect cleanup", () => {
    const roomId = "11111111-1111-1111-1111-111111111111"
    const sectionId = "22222222-2222-2222-2222-222222222222"
    assert.deepEqual(
      parseLegacySectionLiveKitRoomName(`tt/${roomId}/${sectionId}`),
      { roomId, sectionId }
    )
    assert.equal(
      parseLegacySectionLiveKitRoomName(`tt/${roomId}/voice`),
      null
    )
  })

  it("defaults room voice mode to open and labels General Voice", () => {
    assert.equal(normalizeTradeRoomLiveVoiceKind(null), "voice_open")
    assert.equal(tradeRoomSupportsSharedLiveVoice("voice_open"), true)
    assert.equal(tradeRoomSupportsSharedLiveVoice("off"), false)
    assert.equal(TRADE_ROOM_GENERAL_VOICE_LABEL, "General Voice")
  })
})
