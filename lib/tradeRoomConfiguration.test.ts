import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  defaultTradeRoomDraft,
  effectiveJoinPolicy,
  roomRequiresJoinApproval,
  validateTradeRoomConfiguration,
} from "./tradeRoomConfiguration.ts"

describe("tradeRoomConfiguration", () => {
  it("forces approval join policy for private rooms", () => {
    const draft = defaultTradeRoomDraft("trader")
    draft.visibility = "private"
    draft.joinPolicy = "open"
    assert.equal(effectiveJoinPolicy(draft), "approval")
  })

  it("requires join approval for private rooms at runtime", () => {
    assert.equal(
      roomRequiresJoinApproval({ is_private: true, join_policy: "open" }),
      true
    )
    assert.equal(
      roomRequiresJoinApproval({ is_private: false, join_policy: "open" }),
      false
    )
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
