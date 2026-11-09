"use client"

import { canModerateRoomMemberTarget } from "@/lib/tradeRoomModerationPermission.ts"
import { createExternalStoreSnapshotCache } from "./externalStoreSnapshot.ts"

export type TradeRoomLiveModerationUiContext = {
  roomId: string | null
  accessToken: string | null
  viewerUserId: string | null
  ownerUserId: string | null
  canModerateRoom: boolean
  canManageRoom: boolean
  liveVoiceKind: string | null
  tags: { id: string; name: string }[]
  memberTagAssignments: { user_id: string; tag_id: string }[]
}

const EMPTY: TradeRoomLiveModerationUiContext = {
  roomId: null,
  accessToken: null,
  viewerUserId: null,
  ownerUserId: null,
  canModerateRoom: false,
  canManageRoom: false,
  liveVoiceKind: null,
  tags: [],
  memberTagAssignments: [],
}

type Listener = () => void
const listeners = new Set<Listener>()

let context: TradeRoomLiveModerationUiContext = EMPTY

const snapshotCache = createExternalStoreSnapshotCache<TradeRoomLiveModerationUiContext>(
  () => context
)

function emit() {
  snapshotCache.publish(() => context)
  for (const listener of listeners) {
    listener()
  }
}

export function setTradeRoomLiveModerationUiContext(
  next: Partial<TradeRoomLiveModerationUiContext> | null
): void {
  if (next === null) {
    context = EMPTY
    emit()
    return
  }
  context = { ...context, ...next }
  emit()
}

export function subscribeTradeRoomLiveModerationUiContext(listener: Listener): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function getTradeRoomLiveModerationUiContextSnapshot(): TradeRoomLiveModerationUiContext {
  return snapshotCache.getSnapshot()
}

export function moderationUiCanActOnMember(
  ctx: TradeRoomLiveModerationUiContext,
  targetUserId: string
): boolean {
  if (!ctx.canModerateRoom && !ctx.canManageRoom) return false
  const targetTagIds = ctx.memberTagAssignments
    .filter((row) => row.user_id === targetUserId)
    .map((row) => row.tag_id)
  return canModerateRoomMemberTarget({
    viewerId: ctx.viewerUserId,
    ownerUserId: ctx.ownerUserId,
    targetUserId,
    targetTagIds,
    tags: ctx.tags,
    canManageRoom: ctx.canManageRoom,
    canModerateRoom: ctx.canModerateRoom,
  })
}
