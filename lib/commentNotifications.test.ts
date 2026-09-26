import { describe, it } from "node:test"
import {
  buildCommentNotificationInsertPayload,
  ensureCommentNotification,
  resolveCommentNotificationRecipients,
} from "./commentNotifications.ts"
import assert from "node:assert/strict"

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

  it("sends the current session and does not refresh it", async () => {
    const calls: string[] = []
    const supabase = {
      auth: {
        getSession: async () => {
          calls.push("getSession")
          return {
            data: { session: { access_token: "access-token" } },
            error: null,
          }
        },
        refreshSession: async () => {
          calls.push("refreshSession")
          return { data: { session: null }, error: { message: "refresh" } }
        },
      },
    }
    const originalFetch = globalThis.fetch
    let authorization: string | null = null
    globalThis.fetch = async (_input, init) => {
      const headers = new Headers(init?.headers)
      authorization = headers.get("authorization")
      return new Response(JSON.stringify({ ok: true }), { status: 200 })
    }
    try {
      await ensureCommentNotification(supabase as never, {
        recipientUserId: "owner-1",
        senderUserId: "commenter-1",
        commentId: "comment-1",
        content: "Nice trade",
        target: { kind: "trade", tradeId: "trade-1" },
      })
    } finally {
      globalThis.fetch = originalFetch
    }
    assert.deepEqual(calls, ["getSession"])
    assert.equal(authorization, "Bearer access-token")
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
export {}
