import { buildFeedDeepLinkHref } from "@/lib/feedDeepLink"
import {
  buildTradeRoomHref,
  parseRoomJoinContent,
  parseRoomMessageContent,
} from "@/lib/notificationsDisplay"
import { profilePath } from "@/lib/profileRoutes"

export type PushNotificationTarget = {
  type: string
  sender_id?: string | null
  post_id?: string | null
  trade_id?: string | null
  profile_post_id?: string | null
  achievement_post_id?: string | null
  reel_id?: string | null
  comment_id?: string | null
  room_id?: string | null
  content?: string | null
  senderUsername?: string | null
  senderName?: string | null
  recipientUserId?: string | null
  recipientUsername?: string | null
  commentKind?: "comment" | "reply" | "mention"
}

function displayName(target: PushNotificationTarget): string {
  const name = target.senderName?.trim()
  if (name) return name
  const username = target.senderUsername?.trim()
  if (username) return username.startsWith("@") ? username.slice(1) : username
  return "Someone"
}

function parseJsonContent(content: string | null | undefined): Record<string, unknown> | null {
  if (!content?.trim()) return null
  try {
    const parsed = JSON.parse(content) as unknown
    return parsed && typeof parsed === "object"
      ? (parsed as Record<string, unknown>)
      : null
  } catch {
    return null
  }
}

/** Concise native push copy — mirrors inbox semantics, not a second notification system. */
export function buildPushAlertCopy(target: PushNotificationTarget): {
  title: string
  body: string
} {
  const who = displayName(target)
  const type = target.type

  if (type === "like") {
    return { title: "New Like", body: `${who} liked your post` }
  }
  if (type === "comment") {
    if (target.commentKind === "reply") {
      return { title: "New Reply", body: `${who} replied to you` }
    }
    if (target.commentKind === "mention") {
      return { title: "Mention", body: `${who} mentioned you` }
    }
    if (target.achievement_post_id) {
      return { title: "New Comment", body: `${who} commented on your achievement` }
    }
    if (target.trade_id && !target.post_id && !target.profile_post_id) {
      return { title: "New Comment", body: `${who} commented on your trade` }
    }
    return { title: "New Comment", body: `${who} commented on your post` }
  }
  if (type === "follow") {
    return { title: "New Follower", body: `${who} started following you` }
  }
  if (type === "follow_request") {
    return { title: "Follow Request", body: `${who} requested to follow you` }
  }
  if (type === "room_join") {
    const meta = parseRoomJoinContent(target.content)
    const room = meta.room_name?.trim() || "a trade room"
    return { title: "Room Join", body: `${who} joined ${room}` }
  }
  if (type === "room_message") {
    const meta = parseRoomMessageContent(target.content)
    const room = meta.room_name?.trim() || "Trade Room"
    return { title: "Room Message", body: `New message in ${room}` }
  }
  if (type === "affiliate_referral" || type === "affiliate_commission_earned") {
    const json = parseJsonContent(target.content)
    return {
      title: String(json?.title ?? "Affiliate"),
      body: String(json?.body ?? "You have a new affiliate update"),
    }
  }
  if (type === "trading_report") {
    const json = parseJsonContent(target.content)
    return {
      title: String(json?.title ?? "Trading Report"),
      body: String(json?.body ?? "Your trading report is ready"),
    }
  }
  if (type === "message") {
    return { title: "New Message", body: `${who} sent you a message` }
  }

  return { title: "TradeTraxs", body: "You have a new notification" }
}

/** Reuse existing app routes for notification deep links. */
export function buildPushDeepLinkHref(target: PushNotificationTarget): string {
  const type = target.type

  if (type === "like" || type === "comment") {
    if (target.reel_id) {
      return buildFeedDeepLinkHref({
        kind: "reel",
        id: String(target.reel_id),
        openComments: type === "comment" || Boolean(target.comment_id),
      })
    }
    if (target.achievement_post_id) {
      return buildFeedDeepLinkHref({
        kind: "achievement",
        id: String(target.achievement_post_id),
        openComments: type === "comment" || Boolean(target.comment_id),
      })
    }
    if (target.trade_id && !target.post_id && !target.profile_post_id) {
      return buildFeedDeepLinkHref({
        kind: "trade",
        id: String(target.trade_id),
        openComments: type === "comment" || Boolean(target.comment_id),
      })
    }
    const postId = target.post_id || target.profile_post_id
    if (postId) {
      return buildFeedDeepLinkHref({
        kind: "post",
        id: String(postId),
        openComments: type === "comment" || Boolean(target.comment_id),
      })
    }
    return "/notifications"
  }

  if (type === "follow" || type === "follow_request") {
    if (target.sender_id) {
      return profilePath({
        id: String(target.sender_id),
        username: target.senderUsername,
      })
    }
    if (target.recipientUserId) {
      return `${profilePath({
        id: String(target.recipientUserId),
        username: target.recipientUsername,
      })}?followers=1`
    }
    return "/notifications"
  }

  if (type === "room_join") {
    const meta = parseRoomJoinContent(target.content)
    const slug = meta.room_slug?.trim()
    if (slug) return buildTradeRoomHref(slug)
    return "/community"
  }

  if (type === "room_message") {
    const meta = parseRoomMessageContent(target.content)
    const slug = meta.room_slug?.trim()
    if (slug) {
      return buildTradeRoomHref(slug, {
        sectionId: meta.section_id,
        messageId: meta.message_id,
      })
    }
    return "/community"
  }

  if (type === "affiliate_referral" || type === "affiliate_commission_earned") {
    const json = parseJsonContent(target.content)
    const href = typeof json?.href === "string" ? json.href.trim() : ""
    return href.startsWith("/") ? href : "/affiliate/dashboard"
  }

  if (type === "trading_report") {
    const json = parseJsonContent(target.content)
    const href = typeof json?.href === "string" ? json.href.trim() : ""
    return href.startsWith("/") ? href : "/dashboard"
  }

  return "/notifications"
}
