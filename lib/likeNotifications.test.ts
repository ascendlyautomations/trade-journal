import { describe, it } from "node:test"
import { buildLikeNotificationInsertPayload, } from "./likeNotifications.ts"
import assert from "node:assert/strict"

describe("buildLikeNotificationInsertPayload", () => {
  it("builds trade like payload", () => {
    assert.deepEqual(
      buildLikeNotificationInsertPayload({
        recipientUserId: "owner-1",
        senderUserId: "liker-1",
        target: { kind: "trade", tradeId: "trade-1" },
      }),
      {
        user_id: "owner-1",
        sender_id: "liker-1",
        type: "like",
        trade_id: "trade-1",
      }
    )
  })

  it("builds feed post like payload", () => {
    assert.deepEqual(
      buildLikeNotificationInsertPayload({
        recipientUserId: "owner-1",
        senderUserId: "liker-1",
        target: { kind: "post", postId: "post-1", tradeId: "trade-1" },
      }),
      {
        user_id: "owner-1",
        sender_id: "liker-1",
        type: "like",
        post_id: "post-1",
        trade_id: "trade-1",
      }
    )
  })

  it("builds profile post like payload", () => {
    assert.deepEqual(
      buildLikeNotificationInsertPayload({
        recipientUserId: "owner-1",
        senderUserId: "liker-1",
        target: { kind: "profile_post", profilePostId: "pp-1" },
      }),
      {
        user_id: "owner-1",
        sender_id: "liker-1",
        type: "like",
        profile_post_id: "pp-1",
      }
    )
  })
})
export {}
