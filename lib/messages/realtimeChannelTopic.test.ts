import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isRealtimeChannelTopic,
  realtimeChannelTopic,
  realtimeChannelsToReplace,
} from "./realtimeChannelTopic.ts"

describe("DM realtime channel topics", () => {
  it("matches the prefixed topic the client actually stores", () => {
    assert.equal(realtimeChannelTopic("messages-room-1"), "realtime:messages-room-1")
    assert.equal(
      isRealtimeChannelTopic("messages-room-1", "messages-room-1"),
      false
    )
    assert.equal(
      isRealtimeChannelTopic("realtime:messages-room-1", "messages-room-1"),
      true
    )
  })

  it("selects the joined channel that a remount has to remove first", () => {
    const channels = [
      { topic: "realtime:typing-other" },
      { topic: "realtime:messages-room-1" },
      { topic: "messages-room-1" },
    ]
    assert.deepEqual(realtimeChannelsToReplace(channels, "messages-room-1"), [
      { topic: "realtime:messages-room-1" },
    ])
  })
})
