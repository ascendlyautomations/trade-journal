export type NotificationRecord = {
  id: string
  user_id: string
  sender_id: string | null
  type: string
  post_id: string | null
  trade_id: string | null
  content: string | null
  read: boolean
  created_at: string
}

export type SenderProfile = {
  id: string
  username: string | null
  name: string | null
  avatar_url?: string | null
}

export type LikeNotificationGroup = {
  kind: "like_group"
  key: string
  post_id: string | null
  trade_id: string | null
  notificationIds: string[]
  read: boolean
  latestAt: string
  senderIds: string[]
  totalLikes: number
}

export type SingleNotificationItem = {
  kind: "single"
  notification: NotificationRecord
}

export type NotificationListItem = LikeNotificationGroup | SingleNotificationItem

export type TimeSection = "today" | "yesterday" | "earlier"

const DAY_MS = 24 * 60 * 60 * 1000

export function senderDisplayName(
  profile: SenderProfile | undefined,
  fallback = "Someone"
): string {
  return (
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    fallback
  )
}

export function formatLikeGroupMessage(
  names: string[],
  totalLikes: number
): string {
  const ordered = names.filter(Boolean)
  if (totalLikes <= 0) return "Someone liked your post"
  if (totalLikes === 1) {
    return `${ordered[0] ?? "Someone"} liked your post`
  }
  if (totalLikes === 2) {
    const second = ordered[1] ?? "someone else"
    return `${ordered[0] ?? "Someone"} and ${second} liked your post`
  }
  if (ordered.length >= 2) {
    const others = totalLikes - 2
    return `${ordered[0]}, ${ordered[1]} and ${others} other${
      others === 1 ? "" : "s"
    } liked your post`
  }
  const others = totalLikes - 1
  return `${ordered[0] ?? "Someone"} and ${others} other${
    others === 1 ? "" : "s"
  } liked your post`
}

export function groupLikeNotifications(
  rows: NotificationRecord[]
): LikeNotificationGroup[] {
  const byKey = new Map<string, NotificationRecord[]>()

  for (const row of rows) {
    const key = row.post_id
      ? `post:${row.post_id}`
      : row.trade_id
        ? `trade:${row.trade_id}`
        : `like:${row.id}`
    const bucket = byKey.get(key) ?? []
    bucket.push(row)
    byKey.set(key, bucket)
  }

  return Array.from(byKey.entries()).map(([key, bucket]) => {
    const sorted = [...bucket].sort(
      (a, b) =>
        new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    )
    const latest = sorted[0]
    const senderIds: string[] = []
    for (const row of sorted) {
      if (!row.sender_id || senderIds.includes(row.sender_id)) continue
      senderIds.push(row.sender_id)
    }

    return {
      kind: "like_group",
      key,
      post_id: latest.post_id,
      trade_id: latest.trade_id,
      notificationIds: sorted.map((row) => row.id),
      read: sorted.every((row) => row.read),
      latestAt: latest.created_at,
      senderIds,
      totalLikes: sorted.length,
    }
  })
}

export function buildNotificationListItems(
  rows: NotificationRecord[]
): NotificationListItem[] {
  const likes = rows.filter((row) => row.type === "like")
  const others = rows.filter((row) => row.type !== "like")

  const groupedLikes = groupLikeNotifications(likes)
  const singles: SingleNotificationItem[] = others.map((notification) => ({
    kind: "single",
    notification,
  }))

  return [...groupedLikes, ...singles]
}

export function getNotificationTimeSection(
  iso: string,
  now = Date.now()
): TimeSection {
  const date = new Date(iso)
  if (!Number.isFinite(date.getTime())) return "earlier"

  const todayStart = new Date(now)
  todayStart.setHours(0, 0, 0, 0)
  const yesterdayStart = new Date(todayStart.getTime() - DAY_MS)

  if (date.getTime() >= todayStart.getTime()) return "today"
  if (date.getTime() >= yesterdayStart.getTime()) return "yesterday"
  return "earlier"
}

export function groupItemsByTimeSection(items: NotificationListItem[]) {
  const sections: Record<TimeSection, NotificationListItem[]> = {
    today: [],
    yesterday: [],
    earlier: [],
  }

  for (const item of items) {
    const createdAt =
      item.kind === "like_group" ? item.latestAt : item.notification.created_at
    sections[getNotificationTimeSection(createdAt)].push(item)
  }

  const sortByLatest = (a: NotificationListItem, b: NotificationListItem) => {
    const aTime =
      a.kind === "like_group" ? a.latestAt : a.notification.created_at
    const bTime =
      b.kind === "like_group" ? b.latestAt : b.notification.created_at
    return new Date(bTime).getTime() - new Date(aTime).getTime()
  }

  sections.today.sort(sortByLatest)
  sections.yesterday.sort(sortByLatest)
  sections.earlier.sort(sortByLatest)

  return sections
}

export function commentPreview(content: string | null | undefined): string {
  const text = content?.trim() ?? ""
  if (!text) return "New comment on your post"
  if (text.length <= 120) return text
  return `${text.slice(0, 120).trim()}…`
}

export type RoomJoinMeta = {
  room_slug?: string | null
  room_name?: string | null
}

export function parseRoomJoinContent(
  content: string | null | undefined
): RoomJoinMeta {
  if (!content?.trim()) return {}
  try {
    const parsed = JSON.parse(content) as RoomJoinMeta
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch {
    return {}
  }
}

export function formatRoomJoinMessage(username: string): string {
  return `${username} joined your room`
}

export function formatFollowMessage(username: string): string {
  return `${username} started following you`
}

function profileContentHref(
  ownerUserId: string,
  opts: { postId?: string | null; tradeId?: string | null; openComments?: boolean }
): string {
  const base = `/profile/${ownerUserId}`
  if (opts.postId) {
    const params = new URLSearchParams({ post: opts.postId })
    if (opts.openComments) params.set("comments", "1")
    return `${base}?${params.toString()}`
  }
  if (opts.tradeId) {
    return `${base}?trade=${encodeURIComponent(opts.tradeId)}`
  }
  return base
}

export function getNotificationHref(
  item: NotificationListItem,
  ownerUserId: string
): string {
  if (item.kind === "like_group") {
    return profileContentHref(ownerUserId, {
      postId: item.post_id,
      tradeId: item.trade_id,
    })
  }

  const n = item.notification
  if (n.type === "comment") {
    return profileContentHref(ownerUserId, {
      postId: n.post_id,
      tradeId: n.trade_id,
      openComments: Boolean(n.post_id),
    })
  }

  if (n.type === "room_join") {
    const meta = parseRoomJoinContent(n.content)
    const slug = meta.room_slug?.trim()
    if (slug) return `/trade-rooms?room=${encodeURIComponent(slug)}`
    return "/trade-rooms"
  }

  if (n.type === "follow" && n.sender_id) {
    return `/profile/${n.sender_id}`
  }

  if (n.type === "message") return "/messages"

  return "/notifications"
}

export function itemIsUnread(item: NotificationListItem): boolean {
  if (item.kind === "like_group") return !item.read
  return !item.notification.read
}

export function itemCreatedAt(item: NotificationListItem): string {
  return item.kind === "like_group"
    ? item.latestAt
    : item.notification.created_at
}
