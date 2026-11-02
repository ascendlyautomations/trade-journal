export const MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT = 4

export type MobileWebInboxConversation = {
  id: string
  is_group: boolean
  is_pinned: boolean
  name: string | null
  displayName: string
  username: string
  lastMessage?: string | null
}

export type MobileWebInboxTradeRoom = {
  id: string
  name: string
  slug?: string | null
  owner_user_id?: string | null
  image_url?: string | null
  is_private?: boolean | null
  description?: string | null
}

export function normalizeMobileWebInboxTradeRoom(
  raw: unknown
): MobileWebInboxTradeRoom | null {
  if (!raw || typeof raw !== "object") return null
  const row = raw as Record<string, unknown>
  const id = typeof row.id === "string" ? row.id.trim() : ""
  if (!id) return null
  const name =
    typeof row.name === "string" && row.name.trim().length > 0
      ? row.name.trim()
      : "Trade Room"
  const slug = typeof row.slug === "string" && row.slug.trim() ? row.slug : null
  const owner =
    typeof row.owner_user_id === "string" && row.owner_user_id.trim()
      ? row.owner_user_id
      : null
  const image =
    typeof row.image_url === "string" && row.image_url
      ? row.image_url
      : typeof row.avatar_url === "string" && row.avatar_url
        ? row.avatar_url
        : null
  const description =
    typeof row.description === "string" && row.description.trim()
      ? row.description
      : null
  return {
    id,
    name,
    slug,
    owner_user_id: owner,
    image_url: image,
    is_private: row.is_private === true,
    description,
  }
}

export function mobileWebInboxTradeRoomHref(room: {
  id: string
  slug?: string | null
}): string {
  const slug = room.slug?.trim()
  const key = slug && slug.length > 0 ? slug : room.id
  return `/community?room=${encodeURIComponent(key)}`
}

export function conversationMatchesMobileWebInboxSearch(
  conversation: MobileWebInboxConversation,
  query: string
): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  return [conversation.displayName, conversation.username, conversation.name]
    .filter((value): value is string => typeof value === "string" && value.length > 0)
    .some((value) => value.toLowerCase().includes(q))
}

export function roomMatchesMobileWebInboxSearch(
  room: MobileWebInboxTradeRoom,
  query: string
): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  return (
    room.name.toLowerCase().includes(q) ||
    (room.description?.toLowerCase().includes(q) ?? false)
  )
}

export function splitMobileWebMessagesInbox<
  T extends MobileWebInboxConversation,
>({
  conversations,
  rooms,
  viewerId,
  search = "",
}: {
  conversations: T[]
  rooms: MobileWebInboxTradeRoom[]
  viewerId?: string | null
  search?: string
}): {
  pinned: T[]
  directMessages: T[]
  ownedRoom: MobileWebInboxTradeRoom | null
  joinedRooms: MobileWebInboxTradeRoom[]
} {
  const pinned = conversations.filter(
    (conversation) =>
      conversation.is_pinned === true &&
      conversationMatchesMobileWebInboxSearch(conversation, search)
  )
  const directMessages = conversations.filter(
    (conversation) =>
      conversation.is_pinned !== true &&
      conversationMatchesMobileWebInboxSearch(conversation, search)
  )
  const visibleRooms = rooms.filter((room) =>
    roomMatchesMobileWebInboxSearch(room, search)
  )
  const ownedRoom =
    viewerId != null && viewerId.length > 0
      ? (visibleRooms.find((room) => room.owner_user_id === viewerId) ?? null)
      : null
  const joinedRooms = visibleRooms.filter((room) => room.id !== ownedRoom?.id)
  return { pinned, directMessages, ownedRoom, joinedRooms }
}

export function sliceMobileWebInboxPreview<T>(
  items: readonly T[],
  expanded: boolean,
  limit = MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT
): T[] {
  if (expanded || items.length <= limit) return [...items]
  return items.slice(0, limit)
}

export function mobileWebInboxHasVisibleRows({
  pinned,
  directMessages,
  ownedRoom,
  joinedRooms,
}: {
  pinned: readonly unknown[]
  directMessages: readonly unknown[]
  ownedRoom: unknown | null
  joinedRooms: readonly unknown[]
}): boolean {
  return (
    pinned.length > 0 ||
    directMessages.length > 0 ||
    ownedRoom != null ||
    joinedRooms.length > 0
  )
}
