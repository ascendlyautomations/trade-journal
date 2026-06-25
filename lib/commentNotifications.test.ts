const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildCommentNotificationInsertPayload,
  resolveCommentNotificationRecipients,
} = require("./commentNotifications.ts")

describe("resolveCommentNotificationRecipients", () => {
  it("notifies post owner for top-level comments", () => {
    assert.deepEqual(
      resolveCommentNotificationRecipients({
        senderUserId: "user-a",
        ownerUserId: "user-b",
      }),
      ["user-b"]
    )
  })

  it("notifies parent author for replies", () => {
    assert.deepEqual(
      resolveCommentNotificationRecipients({
        senderUserId: "user-a",
        ownerUserId: "user-b",
        parentCommentId: "comment-1",
        existingComments: [{ id: "comment-1", user_id: "user-c" }],
      }),
      ["user-c"]
    )
  })

  it("skips self-notifications", () => {
    assert.deepEqual(
      resolveCommentNotificationRecipients({
        senderUserId: "user-a",
        ownerUserId: "user-a",
      }),
      []
    )
  })
})

describe("buildCommentNotificationInsertPayload", () => {
  it("includes comment_id for trade comments", () => {
    assert.deepEqual(
      buildCommentNotificationInsertPayload({
        recipientUserId: "owner-1",
        senderUserId: "commenter-1",
        commentId: "comment-1",
        content: "Nice trade",
        target: { kind: "trade", tradeId: "trade-1" },
      }),
      {
        user_id: "owner-1",
        sender_id: "commenter-1",
        type: "comment",
        comment_id: "comment-1",
        content: "Nice trade",
        trade_id: "trade-1",
      }
    )
  })

  it("requires commentId", () => {
    assert.throws(
      () =>
        buildCommentNotificationInsertPayload({
          recipientUserId: "owner-1",
          senderUserId: "commenter-1",
          commentId: "",
          content: "hi",
          target: { kind: "trade", tradeId: "trade-1" },
        }),
      /requires commentId/
    )
  })
})
