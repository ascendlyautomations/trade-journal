import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  liveKitBroadcastRoomName,
  parseLiveKitBroadcastRoomName,
  parseLiveKitRoomName,
} from "./liveKitRoomName.ts"
import { mayStartTradeRoomBroadcast } from "./tradeRoomSharedBroadcast.ts"
import { broadcastStartErrorMessageForTest } from "./client/tradeRoomBroadcastErrors.ts"

describe("Trade Room broadcast — room naming", () => {
  it("uses tt/{roomId}/broadcast for LiveKit", () => {
    const roomId = "11111111-1111-4111-8111-111111111111"
    assert.equal(
      liveKitBroadcastRoomName(roomId),
      `tt/${roomId}/broadcast`
    )
    assert.deepEqual(parseLiveKitBroadcastRoomName(`tt/${roomId}/broadcast`), {
      roomId,
    })
    assert.equal(parseLiveKitBroadcastRoomName(`tt/${roomId}/voice`), null)
    assert.equal(parseLiveKitRoomName(`tt/${roomId}/broadcast`), null)
  })
})

describe("Trade Room broadcast — authorization", () => {
  it("allows owner and moderators to go live", () => {
    assert.equal(
      mayStartTradeRoomBroadcast({
        isOwner: true,
        canManage: false,
        canModerate: false,
      }),
      true
    )
    assert.equal(
      mayStartTradeRoomBroadcast({
        isOwner: false,
        canManage: false,
        canModerate: true,
      }),
      true
    )
    assert.equal(
      mayStartTradeRoomBroadcast({
        isOwner: false,
        canManage: false,
        canModerate: false,
      }),
      false
    )
  })
})

describe("Trade Room broadcast — client errors", () => {
  it("maps screen-share cancellation and denial", () => {
    const denied = new Error("Denied")
    denied.name = "NotAllowedError"
    assert.match(broadcastStartErrorMessageForTest(denied), /blocked/i)
    assert.match(
      broadcastStartErrorMessageForTest(new Error("User cancelled")),
      /cancel/i
    )
  })

  it("maps Permissions-Policy camera blocks to camera copy", () => {
    const policy = new Error(
      "Permissions policy violation: camera is not allowed in this document."
    )
    policy.name = "NotAllowedError"
    assert.match(
      broadcastStartErrorMessageForTest(policy),
      /camera access was blocked/i
    )
  })
})
