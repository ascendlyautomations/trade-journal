import type { TradeRoomKind } from "@/lib/tradeRoomManagementPermission"
import { canManageTradeRoom } from "@/lib/tradeRoomManagementPermission"

export const TRADE_ROOM_MODERATOR_TAG_NAME = "Moderator"

const ELEVATED_TAG_NAMES = new Set(
  [TRADE_ROOM_MODERATOR_TAG_NAME, "Admin"].map((n) => n.toLowerCase())
)

export function isElevatedRoomMemberTagName(name: string): boolean {
  return ELEVATED_TAG_NAMES.has(name.trim().toLowerCase())
}

export function memberHasModeratorTag(options: {
  tagIds: string[]
  tags: { id: string; name: string }[]
}): boolean {
  const { tagIds, tags } = options
  for (const tagId of tagIds) {
    const tag = tags.find((t) => t.id === tagId)
    if (
      tag &&
      tag.name.trim().toLowerCase() === TRADE_ROOM_MODERATOR_TAG_NAME.toLowerCase()
    ) {
      return true
    }
  }
  return false
}

export function memberHasElevatedTag(options: {
  tagIds: string[]
  tags: { id: string; name: string }[]
}): boolean {
  const { tagIds, tags } = options
  for (const tagId of tagIds) {
    const tag = tags.find((t) => t.id === tagId)
    if (tag && isElevatedRoomMemberTagName(tag.name)) return true
  }
  return false
}

export function canModerateTradeRoom(options: {
  viewerId: string | null | undefined
  ownerUserId: string | null | undefined
  hasModeratorTag?: boolean
  roomKind?: TradeRoomKind
  isPlatformAdmin?: boolean
}): boolean {
  const { viewerId, ownerUserId, hasModeratorTag, roomKind, isPlatformAdmin } =
    options
  if (
    canManageTradeRoom({
      viewerId,
      ownerUserId,
      roomKind,
      isPlatformAdmin,
    })
  ) {
    return true
  }
  return Boolean(viewerId && hasModeratorTag)
}

export function canAssignRoomMemberTag(options: {
  tagName: string
  canManageRoom: boolean
  canModerateRoom: boolean
}): boolean {
  if (!options.canModerateRoom) return false
  if (options.canManageRoom) return true
  return !isElevatedRoomMemberTagName(options.tagName)
}

export function canModerateRoomMemberTarget(options: {
  viewerId: string | null | undefined
  ownerUserId: string | null | undefined
  targetUserId: string
  targetTagIds: string[]
  tags: { id: string; name: string }[]
  canManageRoom: boolean
  canModerateRoom: boolean
}): boolean {
  const {
    viewerId,
    ownerUserId,
    targetUserId,
    targetTagIds,
    tags,
    canManageRoom,
    canModerateRoom,
  } = options
  if (!viewerId || !canModerateRoom) return false
  if (targetUserId === viewerId) return false
  if (ownerUserId && targetUserId === ownerUserId) return false
  if (canManageRoom) return true
  return !memberHasElevatedTag({ tagIds: targetTagIds, tags })
}
