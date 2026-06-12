import { profilePath } from "./profileRoutes"

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

export type CommentNotificationEntry = {
  id: string
  senderId: string | null
  content: string | null
  created_at: string
}

export type CommentNotificationGroup = {
  kind: "comment_group"
  key: string
  post_id: string | null
  trade_id: string | null
  notificationIds: string[]
  read: boolean
  latestAt: string
  comments: CommentNotificationEntry[]
  totalComments: number
}

export type FollowNotificationGroup = {
  kind: "follow_group"
  key: string
  notificationIds: string[]
  read: boolean
  latestAt: string
  senderIds: string[]
  totalFollows: number
}

export type FollowRequestNotificationGroup = {
  kind: "follow_request_group"
  key: string
  notificationIds: string[]
  read: boolean
  latestAt: string
  senderIds: string[]
  totalRequests: number
}

export type RoomJoinNotificationItem = {
  kind: "room_join"
  notification: NotificationRecord
}

export type GroupedNotificationCard =
  | LikeNotificationGroup
  | CommentNotificationGroup
  | FollowNotificationGroup
  | FollowRequestNotificationGroup
  | RoomJoinNotificationItem

/** @deprecated Use GroupedNotificationCard */
export type SingleNotificationItem = {
  kind: "single"
  notification: NotificationRecord
}

/** @deprecated Use GroupedNotificationCard */
export type NotificationListItem = LikeNotificationGroup | SingleNotificationItem

export type NotificationCenterTab = "all" | "likes" | "comments" | "followers"

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

export type EngagementTarget = "post" | "trade"

export function engagementTarget(
  postId: string | null | undefined,
  tradeId: string | null | undefined
): EngagementTarget {
  if (postId != null && String(postId).trim() !== "") return "post"
  if (tradeId != null && String(tradeId).trim() !== "") return "trade"
  return "post"
}

export function formatLikeGroupMessage(
  names: string[],
  totalLikes: number,
  postId?: string | null,
  tradeId?: string | null
): string {
  const noun = engagementTarget(postId, tradeId)
  const ordered = names.filter(Boolean)
  if (totalLikes <= 0) return `Someone liked your ${noun}`
  if (totalLikes === 1) {
    return `${ordered[0] ?? "Someone"} liked your ${noun}`
  }
  if (totalLikes === 2) {
    const second = ordered[1] ?? "someone else"
    return `${ordered[0] ?? "Someone"} and ${second} liked your ${noun}`
  }
  if (ordered.length >= 2) {
    const others = totalLikes - 2
    return `${ordered[0]}, ${ordered[1]} and ${others} other${
      others === 1 ? "" : "s"
    } liked your ${noun}`
  }
  const others = totalLikes - 1
  return `${ordered[0] ?? "Someone"} and ${others} other${
    others === 1 ? "" : "s"
  } liked your ${noun}`
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

export function formatCommentGroupTitle(
  totalComments: number,
  postId?: string | null,
  tradeId?: string | null
): string {
  const noun = engagementTarget(postId, tradeId)
  const n = Math.max(0, totalComments)
  if (n === 0) return `Someone commented on your ${noun}`
  if (n === 1) return `1 person commented on your ${noun}`
  return `${n} people commented on your ${noun}`
}

export function formatFollowRequestGroupMessage(
  names: string[],
  totalRequests: number
): string {
  const ordered = names.filter(Boolean)
  if (totalRequests <= 0) return "Someone requested to follow you"
  if (totalRequests === 1) {
    return `${ordered[0] ?? "Someone"} requested to follow you`
  }
  if (totalRequests === 2) {
    const second = ordered[1] ?? "someone else"
    return `${ordered[0] ?? "Someone"} and ${second} requested to follow you`
  }
  if (ordered.length >= 2) {
    const others = totalRequests - 2
    return `${ordered[0]}, ${ordered[1]} and ${others} other${
      others === 1 ? "" : "s"
    } requested to follow you`
  }
  const others = totalRequests - 1
  return `${ordered[0] ?? "Someone"} and ${others} other${
    others === 1 ? "" : "s"
  } requested to follow you`
}

export function formatFollowGroupMessage(
  names: string[],
  totalFollows: number
): string {
  const ordered = names.filter(Boolean)
  if (totalFollows <= 0) return "Someone followed you"
  if (totalFollows === 1) {
    return `${ordered[0] ?? "Someone"} followed you`
  }
  if (totalFollows === 2) {
    const second = ordered[1] ?? "someone else"
    return `${ordered[0] ?? "Someone"} and ${second} followed you`
  }
  if (ordered.length >= 2) {
    const others = totalFollows - 2
    return `${ordered[0]}, ${ordered[1]} and ${others} other${
      others === 1 ? "" : "s"
    } followed you`
  }
  const others = totalFollows - 1
  return `${ordered[0] ?? "Someone"} and ${others} other${
    others === 1 ? "" : "s"
  } followed you`
}

function engagementGroupKey(row: NotificationRecord): string {
  if (row.post_id) return `post:${row.post_id}`
  if (row.trade_id) return `trade:${row.trade_id}`
  return `row:${row.id}`
}

export function groupCommentNotifications(
  rows: NotificationRecord[]
): CommentNotificationGroup[] {
  const byKey = new Map<string, NotificationRecord[]>()

  for (const row of rows) {
    const key = engagementGroupKey(row)
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

    return {
      kind: "comment_group",
      key,
      post_id: latest.post_id,
      trade_id: latest.trade_id,
      notificationIds: sorted.map((row) => row.id),
      read: sorted.every((row) => row.read),
      latestAt: latest.created_at,
      totalComments: sorted.length,
      comments: sorted.map((row) => ({
        id: row.id,
        senderId: row.sender_id,
        content: row.content,
        created_at: row.created_at,
      })),
    }
  })
}

/** Rolling 24h bucket index from now (0 = within last 24h). */
export function followRollingBucketKey(iso: string, now = Date.now()): number {
  const t = new Date(iso).getTime()
  if (!Number.isFinite(t)) return Number.MAX_SAFE_INTEGER
  const age = now - t
  if (age < 0) return 0
  return Math.floor(age / DAY_MS)
}

export function groupFollowRequestNotifications(
  rows: NotificationRecord[],
  now = Date.now()
): FollowRequestNotificationGroup[] {
  const byBucket = new Map<number, NotificationRecord[]>()

  for (const row of rows) {
    const bucket = followRollingBucketKey(row.created_at, now)
    const list = byBucket.get(bucket) ?? []
    list.push(row)
    byBucket.set(bucket, list)
  }

  return Array.from(byBucket.entries()).map(([bucket, list]) => {
    const sorted = [...list].sort(
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
      kind: "follow_request_group",
      key: `follow_request:bucket:${bucket}`,
      notificationIds: sorted.map((row) => row.id),
      read: sorted.every((row) => row.read),
      latestAt: latest.created_at,
      senderIds,
      totalRequests: sorted.length,
    }
  })
}

export function groupFollowNotifications(
  rows: NotificationRecord[],
  now = Date.now()
): FollowNotificationGroup[] {
  const byBucket = new Map<number, NotificationRecord[]>()

  for (const row of rows) {
    const bucket = followRollingBucketKey(row.created_at, now)
    const list = byBucket.get(bucket) ?? []
    list.push(row)
    byBucket.set(bucket, list)
  }

  return Array.from(byBucket.entries()).map(([bucket, list]) => {
    const sorted = [...list].sort(
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
      kind: "follow_group",
      key: `follow:bucket:${bucket}`,
      notificationIds: sorted.map((row) => row.id),
      read: sorted.every((row) => row.read),
      latestAt: latest.created_at,
      senderIds,
      totalFollows: sorted.length,
    }
  })
}

export function buildGroupedNotificationCards(
  rows: NotificationRecord[],
  now = Date.now()
): GroupedNotificationCard[] {
  const likes = rows.filter((row) => row.type === "like")
  const comments = rows.filter((row) => row.type === "comment")
  const follows = rows.filter((row) => row.type === "follow")
  const followRequests = rows.filter((row) => row.type === "follow_request")
  const roomJoins = rows.filter((row) => row.type === "room_join")

  const cards: GroupedNotificationCard[] = [
    ...groupLikeNotifications(likes),
    ...groupCommentNotifications(comments),
    ...groupFollowNotifications(follows, now),
    ...groupFollowRequestNotifications(followRequests, now),
    ...roomJoins.map(
      (notification): RoomJoinNotificationItem => ({
        kind: "room_join",
        notification,
      })
    ),
  ]

  cards.sort((a, b) => {
    const aTime = groupedCardCreatedAt(a)
    const bTime = groupedCardCreatedAt(b)
    return new Date(bTime).getTime() - new Date(aTime).getTime()
  })

  return cards
}

export function filterGroupedCardsByTab(
  cards: GroupedNotificationCard[],
  tab: NotificationCenterTab
): GroupedNotificationCard[] {
  switch (tab) {
    case "likes":
      return cards.filter((card) => card.kind === "like_group")
    case "comments":
      return cards.filter((card) => card.kind === "comment_group")
    case "followers":
      return cards.filter(
        (card) =>
          card.kind === "follow_group" || card.kind === "follow_request_group"
      )
    default:
      return cards
  }
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

export function groupedCardCreatedAt(card: GroupedNotificationCard): string {
  if (card.kind === "room_join") return card.notification.created_at
  return card.latestAt
}

export function groupedCardIsUnread(card: GroupedNotificationCard): boolean {
  if (card.kind === "room_join") return !card.notification.read
  return !card.read
}

export function groupedCardNotificationIds(card: GroupedNotificationCard): string[] {
  if (card.kind === "room_join") return [card.notification.id]
  return card.notificationIds
}

export function groupCardsByTimeSection(cards: GroupedNotificationCard[]) {
  const sections: Record<TimeSection, GroupedNotificationCard[]> = {
    today: [],
    yesterday: [],
    earlier: [],
  }

  for (const card of cards) {
    const createdAt = groupedCardCreatedAt(card)
    sections[getNotificationTimeSection(createdAt)].push(card)
  }

  const sortByLatest = (a: GroupedNotificationCard, b: GroupedNotificationCard) =>
    new Date(groupedCardCreatedAt(b)).getTime() -
    new Date(groupedCardCreatedAt(a)).getTime()

  sections.today.sort(sortByLatest)
  sections.yesterday.sort(sortByLatest)
  sections.earlier.sort(sortByLatest)

  return sections
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

export function commentPreview(
  content: string | null | undefined,
  postId?: string | null,
  tradeId?: string | null
): string {
  const text = content?.trim() ?? ""
  if (!text) {
    const noun = engagementTarget(postId, tradeId)
    return `New comment on your ${noun}`
  }
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
  owner: { id: string; username?: string | null },
  opts: { postId?: string | null; tradeId?: string | null; openComments?: boolean }
): string {
  const base = profilePath(owner)
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

export function getGroupedNotificationHref(
  card: GroupedNotificationCard,
  owner: { id: string; username?: string | null },
  sendersById: Record<string, SenderProfile> = {}
): string {
  if (card.kind === "like_group") {
    return profileContentHref(owner, {
      postId: card.post_id,
      tradeId: card.trade_id,
    })
  }

  if (card.kind === "comment_group") {
    return profileContentHref(owner, {
      postId: card.post_id,
      tradeId: card.trade_id,
      openComments: Boolean(card.post_id),
    })
  }

  if (card.kind === "follow_group") {
    const base = profilePath(owner)
    return `${base}?followers=1`
  }

  if (card.kind === "follow_request_group") {
    const senderId = card.senderIds[0]
    if (senderId) {
      const sender = sendersById[senderId]
      return profilePath({ id: senderId, username: sender?.username })
    }
    return profilePath(owner)
  }

  const n = card.notification
  if (n.type === "room_join") {
    const meta = parseRoomJoinContent(n.content)
    const slug = meta.room_slug?.trim()
    if (slug) return `/trade-rooms?room=${encodeURIComponent(slug)}`
    return "/trade-rooms"
  }

  return "/notifications"
}

export function getNotificationHref(
  item: NotificationListItem,
  owner: { id: string; username?: string | null },
  sendersById: Record<string, SenderProfile> = {}
): string {
  if (item.kind === "like_group") {
    return profileContentHref(owner, {
      postId: item.post_id,
      tradeId: item.trade_id,
    })
  }

  const n = item.notification
  if (n.type === "comment") {
    return profileContentHref(owner, {
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
    const sender = sendersById[n.sender_id]
    return profilePath({ id: n.sender_id, username: sender?.username })
  }

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
