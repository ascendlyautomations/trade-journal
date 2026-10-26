import { describe, expect, it } from "vitest"
import {
  canAssignRoomMemberTag,
  canModerateRoomMemberTarget,
  canModerateTradeRoom,
  memberHasModeratorTag,
} from "./tradeRoomModerationPermission"

describe("tradeRoomModerationPermission", () => {
  const tags = [
    { id: "t-mod", name: "Moderator" },
    { id: "t-mentor", name: "Mentor" },
  ]

  it("detects moderator tag on member", () => {
    expect(
      memberHasModeratorTag({ tagIds: ["t-mod"], tags })
    ).toBe(true)
    expect(
      memberHasModeratorTag({ tagIds: ["t-mentor"], tags })
    ).toBe(false)
  })

  it("grants moderate room when viewer has moderator tag", () => {
    expect(
      canModerateTradeRoom({
        viewerId: "u1",
        ownerUserId: "owner",
        hasModeratorTag: true,
      })
    ).toBe(true)
    expect(
      canModerateTradeRoom({
        viewerId: "u1",
        ownerUserId: "owner",
        hasModeratorTag: false,
      })
    ).toBe(false)
  })

  it("owner can manage elevated tags; moderator cannot", () => {
    expect(
      canAssignRoomMemberTag({
        tagName: "Moderator",
        canManageRoom: true,
        canModerateRoom: true,
      })
    ).toBe(true)
    expect(
      canAssignRoomMemberTag({
        tagName: "Moderator",
        canManageRoom: false,
        canModerateRoom: true,
      })
    ).toBe(false)
    expect(
      canAssignRoomMemberTag({
        tagName: "Mentor",
        canManageRoom: false,
        canModerateRoom: true,
      })
    ).toBe(true)
  })

  it("moderator cannot ban another moderator", () => {
    expect(
      canModerateRoomMemberTarget({
        viewerId: "mod-a",
        ownerUserId: "owner",
        targetUserId: "mod-b",
        targetTagIds: ["t-mod"],
        tags,
        canManageRoom: false,
        canModerateRoom: true,
      })
    ).toBe(false)
  })
})
