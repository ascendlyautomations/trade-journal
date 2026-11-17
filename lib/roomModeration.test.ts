import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { canDeleteRoomMessage } from "./roomModeration.ts"

describe("roomModeration", () => {
  const tags = [
    { id: "t-mod", name: "Moderator" },
    { id: "t-mentor", name: "Mentor" },
  ]

  it("moderator cannot delete elevated sender messages", () => {
    assert.equal(
      canDeleteRoomMessage(
        "mod",
        { user_id: "sender" },
        {
          isRoomOwner: false,
          isRoomModerator: true,
          roomOwnerUserId: "owner",
          senderTagIds: ["t-mod"],
          tags,
        }
      ),
      false
    )
    assert.equal(
      canDeleteRoomMessage(
        "mod",
        { user_id: "sender" },
        {
          isRoomOwner: false,
          isRoomModerator: true,
          roomOwnerUserId: "owner",
          senderTagIds: ["t-mentor"],
          tags,
        }
      ),
      true
    )
  })
})