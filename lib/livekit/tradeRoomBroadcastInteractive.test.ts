import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  parseBroadcastChatPayload,
  BROADCAST_CHAT_MAX_LENGTH,
} from "./client/tradeRoomBroadcastChat.ts"
import {
  applyBroadcastChatReactionEvent,
  parseBroadcastChatReactionPayload,
} from "./client/tradeRoomBroadcastChatReaction.ts"
import { parseBroadcastHandPayload } from "./client/tradeRoomBroadcastHand.ts"
import {
  normalizeTradeRoomBroadcastVideoSource,
  normalizeTradeRoomBroadcastVoiceMode,
} from "./tradeRoomBroadcastVoiceMode.ts"
import { isLiveKitParticipantAbsentError } from "./liveKitRoomService.ts"

describe("Trade Room broadcast — voice mode metadata", () => {
  it("normalizes voice and video source", () => {
    assert.equal(normalizeTradeRoomBroadcastVoiceMode("open_voice"), "open_voice")
    assert.equal(normalizeTradeRoomBroadcastVoiceMode("unknown"), "broadcast_only")
    assert.equal(normalizeTradeRoomBroadcastVideoSource("camera"), "camera")
    assert.equal(normalizeTradeRoomBroadcastVideoSource(null), "screen")
  })
})

describe("Trade Room broadcast — raise hand", () => {
  it("rejects spoofed hand identity", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({ type: "hand_state", identity: "attacker", raised: true })
    )
    assert.equal(parseBroadcastHandPayload(payload, "real-user"), null)
  })

  it("accepts matching identity", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({ type: "hand_state", identity: "u1", raised: true })
    )
    const state = parseBroadcastHandPayload(payload, "u1")
    assert.ok(state)
    assert.equal(state.raised, true)
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

  it("parses optional reply snapshot fields", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({
        type: "chat",
        userId: "u1",
        displayName: "User",
        text: "reply body",
        sentAt: 2,
        replyToMessageId: "host-1",
        replyToUserId: "host",
        replyToDisplayName: "Host",
        replyToTextPreview: "hello there",
      })
    )
    const msg = parseBroadcastChatPayload(payload, "u1")
    assert.ok(msg)
    assert.equal(msg?.replyTo?.messageId, "host-1")
    assert.equal(msg?.replyTo?.displayName, "Host")
  })
})

describe("Trade Room broadcast — live chat message reactions", () => {
  it("rejects spoofed userId", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({
        type: "chat_reaction",
        messageId: "m1",
        userId: "attacker",
        emoji: "🔥",
        sentAt: 1,
      })
    )
    assert.equal(parseBroadcastChatReactionPayload(payload, "real-user"), null)
  })

  it("applies one reaction per user per message", () => {
    const payload = new TextEncoder().encode(
      JSON.stringify({
        type: "chat_reaction",
        messageId: "m1",
        userId: "u1",
        emoji: "🔥",
        sentAt: 1,
      })
    )
    const event = parseBroadcastChatReactionPayload(payload, "u1")
    assert.ok(event)
    let rows = applyBroadcastChatReactionEvent([], event!)
    assert.equal(rows.length, 1)
    assert.equal(rows[0]!.emoji, "🔥")

    const replace = parseBroadcastChatReactionPayload(
      new TextEncoder().encode(
        JSON.stringify({
          type: "chat_reaction",
          messageId: "m1",
          userId: "u1",
          emoji: "❤️",
          sentAt: 2,
        })
      ),
      "u1"
    )
    rows = applyBroadcastChatReactionEvent(rows, replace!)
    assert.equal(rows.length, 1)
    assert.equal(rows[0]!.emoji, "❤️")

    const cleared = parseBroadcastChatReactionPayload(
      new TextEncoder().encode(
        JSON.stringify({
          type: "chat_reaction",
          messageId: "m1",
          userId: "u1",
          emoji: null,
          sentAt: 3,
        })
      ),
      "u1"
    )
    rows = applyBroadcastChatReactionEvent(rows, cleared!)
    assert.equal(rows.length, 0)
  })
})
