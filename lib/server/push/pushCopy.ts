import { buildFeedDeepLinkHref } from "@/lib/feedDeepLink"
import {
  buildTradeRoomHref,
  parseRoomJoinContent,
  parseRoomMessageContent,
} from "@/lib/notificationsDisplay"
import { profilePath } from "@/lib/profileRoutes"
import { truncatePushPreview } from "@/lib/server/push/dmPushPreview"

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

/** Prefer display name, then username — professional messaging style. */
export function displayName(target: PushNotificationTarget): string {
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

function stringField(
  json: Record<string, unknown> | null,
  key: string
): string {
  const value = json?.[key]
  return typeof value === "string" ? value.trim() : ""
}

function commentBody(target: PushNotificationTarget): string {
  const raw = String(target.content ?? "").trim()
  if (!raw) return ""
  return truncatePushPreview(raw)
}

function likeTitle(target: PushNotificationTarget, who: string): string {
  if (target.comment_id) return `${who} liked your comment`
  if (target.achievement_post_id) return `${who} liked your achievement`
  if (target.reel_id) return `${who} liked your reel`
  if (target.trade_id && !target.post_id && !target.profile_post_id) {
    return `${who} liked your trade`
  }
  return `${who} liked your post`
}

/** Concise native push copy — professional messaging style, no emojis. */
export function buildPushAlertCopy(target: PushNotificationTarget): {
  title: string
  body: string
} {
  const who = displayName(target)
  const type = target.type
  const json = parseJsonContent(target.content)

  if (type === "like") {
    return { title: likeTitle(target, who), body: "" }
  }

  if (type === "like_batch" || type === "follow_batch") {
    return {
      title: stringField(json, "title") || (type === "follow_batch" ? "New followers" : "New likes"),
      body: stringField(json, "body") || "",
    }
  }

  if (type === "like_milestone") {
    return {
      title: stringField(json, "title") || "Engagement milestone",
      body: stringField(json, "body") || "More traders are engaging with your content.",
    }
  }

  if (type === "comment") {
    const body = commentBody(target)
    if (target.commentKind === "reply") {
      return { title: `${who} replied`, body }
    }
    if (target.commentKind === "mention") {
      return { title: `${who} mentioned you`, body }
    }
    if (target.achievement_post_id) {
      return { title: `${who} commented on your achievement`, body }
    }
    if (target.reel_id) {
      return { title: `${who} commented on your reel`, body }
    }
    if (target.trade_id && !target.post_id && !target.profile_post_id) {
      return { title: `${who} commented on your trade`, body }
    }
    return { title: `${who} commented`, body }
  }

  if (type === "follow") {
    return { title: `${who} followed you`, body: "" }
  }

  if (type === "follow_request") {
    return { title: `${who} requested to follow you`, body: "" }
  }

  if (type === "follow_request_accepted") {
    return { title: `${who} accepted your follow request`, body: "" }
  }

  if (type === "room_join") {
    const meta = parseRoomJoinContent(target.content)
    const room = meta.room_name?.trim() || "a trade room"
    return { title: who, body: `joined ${room}` }
  }

  if (type === "room_message") {
    const meta = parseRoomMessageContent(target.content)
    const room = meta.room_name?.trim() || "Trade Room"
    const preview = meta.message_preview?.trim() || "New message"
    const isDigest = json?.is_digest === true
    if (isDigest) {
      return { title: room, body: preview }
    }
    const senderLabel =
      stringField(json, "sender_name") ||
      stringField(json, "sender_username") ||
      who
    const isReply = json?.is_reply === true
    if (isReply) {
      return {
        title: room,
        body: `${senderLabel} replied: ${preview}`,
      }
    }
    return {
      title: room,
      body: `${senderLabel}: ${preview}`,
    }
  }

  if (type === "room_mention") {
    const meta = parseRoomMessageContent(target.content)
    const room = meta.room_name?.trim() || "Trade Room"
    const preview = meta.message_preview?.trim() || ""
    const senderLabel =
      stringField(json, "sender_name") ||
      stringField(json, "sender_username") ||
      who
    return {
      title: room,
      body: preview
        ? `${senderLabel} mentioned you: ${preview}`
        : `${senderLabel} mentioned you`,
    }
  }

  if (type === "affiliate_referral" || type === "affiliate_commission_earned") {
    return {
      title: stringField(json, "title") || "Affiliate update",
      body: stringField(json, "body") || "You have a new affiliate update.",
    }
  }

  if (type === "trading_report") {
    return {
      title: stringField(json, "title") || "Trading report",
      body:
        stringField(json, "body") || "Your trading summary is ready to review.",
    }
  }

  if (type === "message") {
    const preview = stringField(json, "message_preview") || "New message"
    const isGroup = json?.is_group === true
    const groupName = stringField(json, "group_name")

    if (isGroup && groupName) {
      return {
        title: groupName,
        body: `${who}: ${preview}`,
      }
    }
    return {
      title: who,
      body: preview,
    }
  }

  return { title: "TradeTraxs", body: "You have a new notification" }
}

/** Reuse existing app routes for notification deep links. */
export function buildPushDeepLinkHref(target: PushNotificationTarget): string {
  const type = target.type

  if (type === "like" || type === "like_milestone" || type === "like_batch" || type === "comment") {
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

  if (
    type === "follow" ||
    type === "follow_request" ||
    type === "follow_request_accepted" ||
    type === "follow_batch"
  ) {
    if (type === "follow_batch") {
      const json = parseJsonContent(target.content)
      const href = typeof json?.href === "string" ? json.href.trim() : ""
      if (href.startsWith("/")) return href
    }
    if (target.sender_id) {
      // Prefer UUID path so native profile loads by id (username paths break ProfileID lookup).
      return `/profile/${String(target.sender_id).trim()}`
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

  if (type === "room_message" || type === "room_mention") {
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

  if (type === "message") {
    const json = parseJsonContent(target.content)
    const conversationId =
      typeof json?.conversation_id === "string"
        ? json.conversation_id.trim()
        : ""
    if (conversationId) return `/messages/${conversationId}`
    return "/messages"
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
