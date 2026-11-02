import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  canAssignRoomMemberTag,
  canModerateRoomMemberTarget,
  canModerateTradeRoom,
  memberHasModeratorTag,
} from "./tradeRoomModerationPermission.ts"

describe("tradeRoomModerationPermission", () => {
  const tags = [
    { id: "t-mod", name: "Moderator" },
    { id: "t-mentor", name: "Mentor" },
  ]

  it("detects moderator tag on member", () => {
    assert.equal(
      memberHasModeratorTag({ tagIds: ["t-mod"], tags }),
      true
    )
    assert.equal(
      memberHasModeratorTag({ tagIds: ["t-mentor"], tags }),
      false
    )
  })

  it("grants moderate room when viewer has moderator tag", () => {
    assert.equal(
      canModerateTradeRoom({
        viewerId: "u1",
        ownerUserId: "owner",
        hasModeratorTag: true,
      }),
      true
    )
    assert.equal(
      canModerateTradeRoom({
        viewerId: "u1",
        ownerUserId: "owner",
        hasModeratorTag: false,
      }),
      false
    )
  })

  it("owner can manage elevated tags; moderator cannot", () => {
    assert.equal(
      canAssignRoomMemberTag({
        tagName: "Moderator",
        canManageRoom: true,
        canModerateRoom: true,
      }),
      true
    )
    assert.equal(
      canAssignRoomMemberTag({
        tagName: "Moderator",
        canManageRoom: false,
        canModerateRoom: true,
      }),
      false
    )
    assert.equal(
      canAssignRoomMemberTag({
        tagName: "Mentor",
        canManageRoom: false,
        canModerateRoom: true,
      }),
      true
    )
  })

  it("moderator cannot ban another moderator", () => {
    assert.equal(
      canModerateRoomMemberTarget({
        viewerId: "mod-a",
        ownerUserId: "owner",
        targetUserId: "mod-b",
        targetTagIds: ["t-mod"],
        tags,
        canManageRoom: false,
        canModerateRoom: true,
      }),
      false
    )
  })
})
