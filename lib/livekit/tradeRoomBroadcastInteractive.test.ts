import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  parseBroadcastChatPayload,
  BROADCAST_CHAT_MAX_LENGTH,
} from "./client/tradeRoomBroadcastChat.ts"
import {
  normalizeTradeRoomBroadcastVideoSource,
  normalizeTradeRoomBroadcastVoiceMode,
} from "./tradeRoomBroadcastVoiceMode.ts"

describe("Trade Room broadcast — voice mode metadata", () => {
  it("normalizes voice and video source", () => {
    assert.equal(normalizeTradeRoomBroadcastVoiceMode("open_voice"), "open_voice")
    assert.equal(normalizeTradeRoomBroadcastVoiceMode("unknown"), "broadcast_only")
    assert.equal(normalizeTradeRoomBroadcastVideoSource("camera"), "camera")
    assert.equal(normalizeTradeRoomBroadcastVideoSource(null), "screen")
  })
})

describe("Trade Room broadcast — live chat", () => {
  it("rejects spoofed userId in chat payload", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({
        type: "chat",
        userId: "attacker",
        displayName: "Attacker",
        avatarUrl: null,
        text: "hello",
        sentAt: Date.now(),
      })
    )
    assert.equal(parseBroadcastChatPayload(payload, "real-user"), null)
  })

  it("accepts matching identity and enforces max length", () => {
    const long = "x".repeat(BROADCAST_CHAT_MAX_LENGTH + 1)
    const bad = new TextEncoder().encode(
      JSON.stringify({
        type: "chat",
        userId: "u1",
        displayName: "User",
        text: long,
        sentAt: 1,
      })
    )
    assert.equal(parseBroadcastChatPayload(bad, "u1"), null)

    const good = new TextEncoder().encode(
      JSON.stringify({
        type: "chat",
        userId: "u1",
        displayName: "User",
        text: " hi ",
        sentAt: 1,
      })
    )
    const msg = parseBroadcastChatPayload(good, "u1")
    assert.ok(msg)
    assert.equal(msg.text, "hi")
  })
})
