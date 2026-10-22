import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  defaultTradeRoomDraft,
  effectiveJoinPolicy,
  validateTradeRoomConfiguration,
} from "./tradeRoomConfiguration.ts"

describe("tradeRoomConfiguration", () => {
  it("forces open join policy for private rooms", () => {
    const draft = defaultTradeRoomDraft("trader")
    draft.visibility = "private"
    draft.joinPolicy = "approval"
    assert.equal(effectiveJoinPolicy(draft), "open")
  })

  it("requires at least one channel on create", () => {
    const draft = defaultTradeRoomDraft("trader")
    draft.channels = []
    assert.match(
      validateTradeRoomConfiguration(draft) ?? "",
      /sub-room/i
    )
  })
})
