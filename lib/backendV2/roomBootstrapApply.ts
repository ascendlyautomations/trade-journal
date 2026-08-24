import type { Dispatch, SetStateAction } from "react"
import type { RoomBootstrapV1, RoomMessageV1 } from "./roomContracts.ts"

export type RoomBootstrapApplyTarget = {
  setSections: Dispatch<SetStateAction<any[]>>
  setSelectedSectionId: Dispatch<SetStateAction<string | null>>
  setPinnedMessages: Dispatch<SetStateAction<any[]>>
  setMessages: Dispatch<SetStateAction<any[]>>
  setHasOlderMessages: Dispatch<SetStateAction<boolean>>
  setLoadingMessages: Dispatch<SetStateAction<boolean>>
  setRoomNotificationsEnabled: Dispatch<SetStateAction<boolean>>
  setChannelNotificationPrefs: Dispatch<SetStateAction<Record<string, boolean>>>
  setActiveMembers: Dispatch<SetStateAction<number>>
  setLeftMembers: Dispatch<SetStateAction<number>>
  setUnreadByRoomId: Dispatch<
    SetStateAction<Record<string, boolean>>
  >
  patchRoomSectionsInSession: (
    userId: string,
    roomId: string,
    payload: {
      list: RoomBootstrapV1["data"]["sections"]
      activeSectionId: string | null
    }
  ) => void
  patchRoomMessagesInSession: (
    userId: string,
    cacheKey: string,
    payload: { pinned: unknown[]; main: unknown[]; hasOlder?: boolean }
  ) => void
  buildRoomMessagesCacheKey: (
    roomId: string,
    sections: { id: string; name?: string | null }[],
    activeSectionId: string | null
  ) => string
  messagesByRoomRef: {
    current: Record<
      string,
      { pinned: unknown[]; main: unknown[]; hasOlder?: boolean }
    >
  }
  setMessagesByRoom: Dispatch<
    SetStateAction<
      Record<string, { pinned: any[]; main: any[]; hasOlder?: boolean }>
    >
  >
  markedReadRoomKeyRef: { current: string | null }
}

export function mapRoomBootstrapMessages(messages: RoomMessageV1[]): unknown[] {
  return messages as unknown[]
}

export function applyRoomBootstrapToCommunityState(
  bootstrap: RoomBootstrapV1,
  roomId: string,
  userId: string,
  target: RoomBootstrapApplyTarget
): void {
  const {
    sections,
    active_section_id: activeSectionId,
    pinned_messages: pinned,
    messages,
    has_more_messages: hasMore,
    membership,
    channel_preferences: channelPrefs,
    member_stats: memberStats,
    unread_count: unreadCount,
    mark_read: markRead,
  } = bootstrap.data

  target.setSections(sections)
  target.setSelectedSectionId(activeSectionId)
  target.setPinnedMessages(mapRoomBootstrapMessages(pinned))
  target.setMessages(mapRoomBootstrapMessages(messages))
  target.setHasOlderMessages(hasMore)
  target.setLoadingMessages(false)
  target.setRoomNotificationsEnabled(membership.notification_enabled)
  target.setChannelNotificationPrefs(channelPrefs)

  if (memberStats) {
    target.setActiveMembers(memberStats.active_members)
    target.setLeftMembers(memberStats.left_members)
  }

  const cacheKey = target.buildRoomMessagesCacheKey(
    roomId,
    sections,
    activeSectionId
  )
  target.messagesByRoomRef.current[cacheKey] = {
    pinned: mapRoomBootstrapMessages(pinned),
    main: mapRoomBootstrapMessages(messages),
    hasOlder: hasMore,
  }
  target.setMessagesByRoom((prev) => ({
    ...prev,
    [cacheKey]: target.messagesByRoomRef.current[cacheKey]!,
  }))

  target.patchRoomSectionsInSession(userId, roomId, {
    list: sections,
    activeSectionId,
  })
  target.patchRoomMessagesInSession(userId, cacheKey, {
    pinned: mapRoomBootstrapMessages(pinned),
    main: mapRoomBootstrapMessages(messages),
    hasOlder: hasMore,
  })

  if (markRead.applied) {
    target.markedReadRoomKeyRef.current = `${roomId}:${userId}`
    target.setUnreadByRoomId((prev) => ({
      ...prev,
      [roomId]: unreadCount > 0,
    }))
  }
}

export function roomBootstrapEffectsKey(roomId: string): string {
  return roomId
}

/** Section switch — messages/pagination only; preserves membership/stats from room open. */
export function applyRoomBootstrapSectionSwitch(
  bootstrap: RoomBootstrapV1,
  roomId: string,
  userId: string,
  target: RoomBootstrapApplyTarget
): void {
  const {
    active_section_id: activeSectionId,
    pinned_messages: pinned,
    messages,
    has_more_messages: hasMore,
  } = bootstrap.data

  target.setSelectedSectionId(activeSectionId)
  target.setPinnedMessages(mapRoomBootstrapMessages(pinned))
  target.setMessages(mapRoomBootstrapMessages(messages))
  target.setHasOlderMessages(hasMore)
  target.setLoadingMessages(false)

  const sections = bootstrap.data.sections
  const cacheKey = target.buildRoomMessagesCacheKey(
    roomId,
    sections,
    activeSectionId
  )
  target.messagesByRoomRef.current[cacheKey] = {
    pinned: mapRoomBootstrapMessages(pinned),
    main: mapRoomBootstrapMessages(messages),
    hasOlder: hasMore,
  }
  target.setMessagesByRoom((prev) => ({
    ...prev,
    [cacheKey]: target.messagesByRoomRef.current[cacheKey]!,
  }))
  target.patchRoomMessagesInSession(userId, cacheKey, {
    pinned: mapRoomBootstrapMessages(pinned),
    main: mapRoomBootstrapMessages(messages),
    hasOlder: hasMore,
  })
}
