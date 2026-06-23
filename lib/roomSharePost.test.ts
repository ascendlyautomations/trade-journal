const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  buildRoomSharePostInsert,
  formatRoomMemberCount,
  isRoomSharePost,
  pendingRoomShareFromRoom,
} = require("./roomSharePost.ts")

describe("roomSharePost", () => {
  it("detects room share posts by room_id", () => {
    assert.equal(isRoomSharePost({ room_id: "abc" }), true)
    assert.equal(isRoomSharePost({ room_id: "" }), false)
    assert.equal(isRoomSharePost({ content: "hello" }), false)
  })

  it("builds insert payload with room snapshot fields", () => {
    const payload = buildRoomSharePostInsert(
      "user-1",
      {
        roomId: "room-1",
        roomName: "Alpha Room",
        roomLogo: "https://example.com/logo.png",
        roomDescription: "Futures discussion",
      },
      "Join us",
      null
    )

    assert.equal(payload.user_id, "user-1")
    assert.equal(payload.room_id, "room-1")
    assert.equal(payload.room_name, "Alpha Room")
    assert.equal(payload.content, "Join us")
  })

  it("formats member counts", () => {
    assert.equal(formatRoomMemberCount(1), "1 member")
    assert.equal(formatRoomMemberCount(12), "12 members")
  })

  it("maps room rows into composer drafts", () => {
    const draft = pendingRoomShareFromRoom({
      id: "room-1",
      name: "Beta Room",
      description: "Charts",
      image_url: "https://example.com/a.png",
    })

    assert.equal(draft.roomId, "room-1")
    assert.equal(draft.roomName, "Beta Room")
    assert.equal(draft.roomDescription, "Charts")
  })
})
