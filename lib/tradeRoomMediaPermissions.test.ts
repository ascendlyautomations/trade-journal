import assert from "node:assert/strict"
import test from "node:test"
import { tradeRoomMemberCanShareMedia } from "./tradeRoomMediaPermissions.ts"

test("tradeRoomMemberCanShareMedia owner bypass", () => {
  assert.equal(
    tradeRoomMemberCanShareMedia({ members_can_share_media: false }, true),
    true
  )
})

test("tradeRoomMemberCanShareMedia respects room flag", () => {
  assert.equal(
    tradeRoomMemberCanShareMedia({ members_can_share_media: false }, false),
    false
  )
  assert.equal(
    tradeRoomMemberCanShareMedia({ members_can_share_media: true }, false),
    true
  )
})
