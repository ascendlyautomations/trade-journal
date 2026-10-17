import { describe, it } from "node:test"
import { DELETED_USER_LABEL, isDirectConversationPeerDeleted, isOrphanedDirectConversation, resolveDmSenderDisplay, } from "./deletedUserDisplay.ts"
import assert from "node:assert/strict"

describe("resolveDmSenderDisplay", () => {
  it("returns Deleted User when sender_anonymized is true", () => {
    const result = resolveDmSenderDisplay({
      sender_id: null,
      sender_anonymized: true,
    })
    assert.equal(result.username, DELETED_USER_LABEL)
    assert.equal(result.isDeleted, true)
    assert.equal(result.profileLinkEnabled, false)
    assert.equal(result.userId, null)
  })

  it("returns profile link for active senders", () => {
    const result = resolveDmSenderDisplay({
      sender_id: "user-1",
      sender_anonymized: false,
      profiles: { username: "trader_one" },
    })
    assert.equal(result.username, "trader_one")
    assert.equal(result.isDeleted, false)
    assert.equal(result.profileLinkEnabled, true)
    assert.equal(result.userId, "user-1")
  })

  it("treats missing profile as deleted sender", () => {
    const result = resolveDmSenderDisplay({
      sender_id: "user-1",
      sender_anonymized: false,
      profiles: null,
    })
    assert.equal(result.username, DELETED_USER_LABEL)
    assert.equal(result.isDeleted, true)
    assert.equal(result.profileLinkEnabled, false)
  })
})

describe("isDirectConversationPeerDeleted", () => {
  it("detects deleted peer in 1:1 threads with history", () => {
    assert.equal(
      isDirectConversationPeerDeleted(false, null, true),
      true
    )
  })

  it("ignores group chats", () => {
    assert.equal(
      isDirectConversationPeerDeleted(true, null, true),
      false
    )
  })
})

describe("isOrphanedDirectConversation", () => {
  it("hides a 1:1 after the other participant row is gone", () => {
    assert.equal(
      isOrphanedDirectConversation(false, [{ user_id: "viewer" }], "viewer"),
      true
    )
  })

  it("keeps a 1:1 when the other participant still exists without a profile", () => {
    assert.equal(
      isOrphanedDirectConversation(
        false,
        [{ user_id: "viewer" }, { user_id: "peer" }],
        "viewer"
      ),
      false
    )
  })

  it("keeps group chats when one member row is gone", () => {
    assert.equal(
      isOrphanedDirectConversation(true, [{ user_id: "viewer" }], "viewer"),
      false
    )
  })

  it("does not treat an empty participant list as deletion", () => {
    assert.equal(isOrphanedDirectConversation(false, [], "viewer"), false)
    assert.equal(isOrphanedDirectConversation(false, null, "viewer"), false)
  })
})
export {}
