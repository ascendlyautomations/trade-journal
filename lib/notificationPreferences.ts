export const NOTIFICATION_PREFERENCES_SELECT = `
  user_id,
  notifications_enabled,
  likes_enabled,
  comments_enabled,
  replies_enabled,
  mentions_enabled,
  reactions_enabled,
  followers_enabled,
  follow_requests_enabled,
  follow_request_accepts_enabled,
  direct_messages_enabled,
  story_replies_enabled,
  shares_enabled,
  room_messages_enabled,
  room_mentions_enabled,
  room_joins_enabled,
  achievement_likes_enabled,
  achievement_comments_enabled,
  achievement_unlocks_enabled,
  product_updates_enabled,
  maintenance_enabled,
  announcements_enabled,
  updated_at
` as const

export type NotificationPreferences = {
  user_id: string
  notifications_enabled: boolean
  likes_enabled: boolean
  comments_enabled: boolean
  replies_enabled: boolean
  mentions_enabled: boolean
  reactions_enabled: boolean
  followers_enabled: boolean
  follow_requests_enabled: boolean
  follow_request_accepts_enabled: boolean
  direct_messages_enabled: boolean
  story_replies_enabled: boolean
  shares_enabled: boolean
  room_messages_enabled: boolean
  room_mentions_enabled: boolean
  room_joins_enabled: boolean
  achievement_likes_enabled: boolean
  achievement_comments_enabled: boolean
  achievement_unlocks_enabled: boolean
  product_updates_enabled: boolean
  maintenance_enabled: boolean
  announcements_enabled: boolean
  updated_at: string | null
}

export type NotificationPreferenceKey = Exclude<
  keyof NotificationPreferences,
  "user_id" | "updated_at"
>

export type CommentNotificationKind = "comment" | "reply" | "mention"

export const DEFAULT_NOTIFICATION_PREFERENCES: Omit<
  NotificationPreferences,
  "user_id" | "updated_at"
> = {
  notifications_enabled: true,
  likes_enabled: true,
  comments_enabled: true,
  replies_enabled: true,
  mentions_enabled: true,
  reactions_enabled: true,
  followers_enabled: true,
  follow_requests_enabled: true,
  follow_request_accepts_enabled: true,
  direct_messages_enabled: true,
  story_replies_enabled: true,
  shares_enabled: true,
  room_messages_enabled: true,
  room_mentions_enabled: true,
  room_joins_enabled: true,
  achievement_likes_enabled: true,
  achievement_comments_enabled: true,
  achievement_unlocks_enabled: true,
  product_updates_enabled: true,
  maintenance_enabled: true,
  announcements_enabled: true,
}

export function mapNotificationPreferencesRow(
  row: Record<string, unknown> | null | undefined,
  userId: string
): NotificationPreferences {
  const bool = (value: unknown, fallback = true) =>
    typeof value === "boolean" ? value : fallback

  return {
    user_id: String(row?.user_id ?? userId),
    notifications_enabled: bool(row?.notifications_enabled),
    likes_enabled: bool(row?.likes_enabled),
    comments_enabled: bool(row?.comments_enabled),
    replies_enabled: bool(row?.replies_enabled),
    mentions_enabled: bool(row?.mentions_enabled),
    reactions_enabled: bool(row?.reactions_enabled),
    followers_enabled: bool(row?.followers_enabled),
    follow_requests_enabled: bool(row?.follow_requests_enabled),
    follow_request_accepts_enabled: bool(row?.follow_request_accepts_enabled),
    direct_messages_enabled: bool(row?.direct_messages_enabled),
    story_replies_enabled: bool(row?.story_replies_enabled),
    shares_enabled: bool(row?.shares_enabled),
    room_messages_enabled: bool(row?.room_messages_enabled),
    room_mentions_enabled: bool(row?.room_mentions_enabled),
    room_joins_enabled: bool(row?.room_joins_enabled),
    achievement_likes_enabled: bool(row?.achievement_likes_enabled),
    achievement_comments_enabled: bool(row?.achievement_comments_enabled),
    achievement_unlocks_enabled: bool(row?.achievement_unlocks_enabled),
    product_updates_enabled: bool(row?.product_updates_enabled),
    maintenance_enabled: bool(row?.maintenance_enabled),
    announcements_enabled: bool(row?.announcements_enabled),
    updated_at:
      row?.updated_at != null ? String(row.updated_at) : null,
  }
}

export function isCommentNotificationAllowed(
  prefs: NotificationPreferences,
  kind: CommentNotificationKind,
  isAchievement: boolean
): boolean {
  if (!prefs.notifications_enabled) return false
  if (isAchievement) return prefs.achievement_comments_enabled
  if (kind === "reply") return prefs.replies_enabled
  if (kind === "mention") return prefs.mentions_enabled
  return prefs.comments_enabled
}

export function isNotificationPreferenceEnabled(
  prefs: NotificationPreferences,
  key: NotificationPreferenceKey
): boolean {
  if (!prefs.notifications_enabled && key !== "notifications_enabled") {
    return false
  }
  return Boolean(prefs[key])
}
