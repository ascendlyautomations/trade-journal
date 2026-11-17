import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

describe("broadcast poll visibility", () => {
  const src = readFileSync(
    new URL("./tradeRoomBroadcastStore.ts", import.meta.url),
    "utf8"
  )
  const handler = src.slice(
    src.indexOf("function onBroadcastPollVisibility"),
    src.indexOf("function ensureBroadcastPollVisibilityListener")
  )
  const clearTimers = src.slice(
    src.indexOf("function clearBroadcastPollTimers"),
    src.indexOf("function resumeBroadcastPollTimers")
  )

  it("suspends HTTP polls while the tab is hidden and refreshes when it returns", () => {
    assert.match(handler, /broadcastPollDocumentHidden\(\)/)
    assert.match(handler, /clearBroadcastPollTimers\(\)/)
    assert.match(handler, /resumeBroadcastPollTimers\(\)/)
    assert.match(clearTimers, /clearInterval\(interactivePollTimer\)/)
    assert.match(clearTimers, /clearInterval\(roomStatusPollTimer\)/)
    assert.doesNotMatch(handler, /disconnect\(/)
    assert.doesNotMatch(handler, /setMicrophoneEnabled/)
    assert.doesNotMatch(clearTimers, /disconnect\(/)
  })
})
