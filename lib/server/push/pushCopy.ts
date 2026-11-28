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
  story_id?: string | null
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

function commentPreviewText(target: PushNotificationTarget): string {
  const raw = String(target.content ?? "").trim()
  if (!raw) return ""
  return truncatePushPreview(raw)
}

function quotedPreview(preview: string): string {
  const trimmed = preview.trim()
  if (!trimmed) return ""
  return `"${trimmed}"`
}

function engagementContentNoun(target: PushNotificationTarget): string {
  if (target.comment_id) return "comment"
  if (target.story_id) return "story"
  if (target.achievement_post_id) return "achievement"
  if (target.reel_id) return "clip"
  if (target.trade_id && !target.post_id && !target.profile_post_id) {
    return "trade"
  }
  return "post"
}

function milestoneEntityNoun(entityKind: string): string {
  switch (entityKind) {
    case "trade":
      return "trade"
    case "reel":
      return "clip"
    case "achievement_post":
      return "achievement"
    case "story":
      return "story"
    case "post":
    case "profile_post":
    default:
      return "post"
  }
}

/** Concise native push copy — short Title Case titles, details in the body. */
export function buildPushAlertCopy(target: PushNotificationTarget): {
  title: string
  body: string
} {
  const who = displayName(target)
  const type = target.type
  const json = parseJsonContent(target.content)

  if (type === "like") {
    const noun = engagementContentNoun(target)
    return {
      title: "New Like",
      body: `${who} liked your ${noun}.`,
    }
  }

  if (type === "like_batch" || type === "follow_batch") {
    return {
      title:
        stringField(json, "title") ||
        (type === "follow_batch" ? "New Followers" : "New Likes"),
      body: stringField(json, "body") || "",
    }
  }

  if (type === "like_milestone") {
    const milestone = json?.milestone
    const entityKind = stringField(json, "entity_kind")
    const noun = milestoneEntityNoun(entityKind)
    const count =
      typeof milestone === "number" && Number.isFinite(milestone)
        ? milestone.toLocaleString("en-US")
        : ""
    const body =
      count && noun
        ? `Your ${noun} reached ${count} likes.`
        : stringField(json, "body") ||
          "Your content reached a new like milestone."
    return {
      title: "Engagement Milestone",
      body,
    }
  }

  if (type === "comment") {
    const preview = commentPreviewText(target)
    const quoted = quotedPreview(preview)
    if (target.commentKind === "reply") {
      return {
        title: "Comment Reply",
        body: quoted
          ? `${who} replied to your comment: ${quoted}`
          : `${who} replied to your comment.`,
      }
    }
    if (target.commentKind === "mention") {
      return {
        title: "New Mention",
        body: quoted
          ? `${who} mentioned you: ${quoted}`
          : `${who} mentioned you.`,
      }
    }
    return {
      title: "New Comment",
      body: quoted
        ? `${who} commented: ${quoted}`
        : `${who} commented on your ${engagementContentNoun(target)}.`,
    }
  }

  if (type === "follow") {
    return {
      title: "New Follower",
      body: `${who} started following you.`,
    }
  }

  if (type === "follow_request") {
    return {
      title: "Follow Request",
      body: `${who} requested to follow you.`,
    }
  }

  if (type === "follow_request_accepted") {
    return {
      title: "Follow Request Accepted",
      body: `${who} accepted your follow request.`,
    }
  }

  if (type === "room_join") {
    const meta = parseRoomJoinContent(target.content)
    const room = meta.room_name?.trim() || "a Trade Room"
    return {
      title: "New Room Member",
      body: `${who} joined ${room}.`,
    }
  }

  if (type === "trade_room_join_request") {
    const room =
      stringField(json, "room_name") ||
      stringField(json, "room_slug") ||
      "a Trade Room"
    return {
      title: "Room Join Request",
      body: `${who} requested to join ${room}.`,
    }
  }

  if (type === "trade_room_join_accepted") {
    const room =
      stringField(json, "room_name") ||
      stringField(json, "room_slug") ||
      "the Trade Room"
    return {
      title: "Join Request Accepted",
      body: `Your request to join ${room} was accepted.`,
    }
  }

  if (type === "trade_room_join_declined") {
    const room =
      stringField(json, "room_name") ||
      stringField(json, "room_slug") ||
      "the Trade Room"
    return {
      title: "Join Request Declined",
      body: `Your request to join ${room} was declined.`,
    }
  }

  if (type === "room_live") {
    const streamTitle = stringField(json, "stream_title")
    const room =
      stringField(json, "room_name") ||
      stringField(json, "room_slug") ||
      "Trade Room"
    const title = streamTitle ? `Live Now: ${streamTitle}` : "Live Now"
    return {
      title,
      body: `${who} is live in ${room}. Tap to watch.`,
    }
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
    const quoted = quotedPreview(preview)
    return {
      title: room,
      body: quoted
        ? `${senderLabel} mentioned you: ${quoted}`
        : `${senderLabel} mentioned you.`,
    }
  }

  if (type === "affiliate_referral") {
    return {
      title: "New Referral",
      body:
        stringField(json, "body") ||
        "Someone signed up using your referral code.",
    }
  }

  if (type === "affiliate_commission_earned") {
    return {
      title: "Commission Earned",
      body:
        stringField(json, "body") ||
        "You earned a commission from a referred subscription.",
    }
  }

  if (type === "trading_report") {
    const kind = stringField(json, "kind")
    const monthly = kind === "monthly"
    return {
      title: monthly ? "Monthly Report" : "Weekly Report",
      body: monthly
        ? "Your monthly performance report is ready."
        : "Your weekly performance report is ready.",
    }
  }

  if (type === "message") {
    const preview = stringField(json, "message_preview") || "New message"
    const messageType = stringField(json, "message_type")
    const isGroup = json?.is_group === true
    const groupName = stringField(json, "group_name")

    if (messageType === "story_reply") {
      const quoted = quotedPreview(preview)
      return {
        title: "Story Reply",
        body: quoted
          ? `${who} replied to your story: ${quoted}`
          : `${who} replied to your story.`,
      }
    }

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

  return { title: "TradeTraxs", body: "You have a new notification." }
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

  if (type === "room_join" || type === "trade_room_join_accepted") {
    const meta = parseRoomJoinContent(target.content)
    const slug = meta.room_slug?.trim()
    if (slug) return buildTradeRoomHref(slug)
    if (target.room_id) return `/community?room=${String(target.room_id)}`
    return "/community"
  }

  if (type === "trade_room_join_request") {
    const json = parseJsonContent(target.content)
    const href = stringField(json, "href")
    if (href.startsWith("/")) return href
    const joinRequestId = stringField(json, "join_request_id")
    if (joinRequestId) {
      return `/notifications?joinRequest=${encodeURIComponent(joinRequestId)}`
    }
    return "/notifications"
  }

  if (type === "trade_room_join_declined") {
    return "/notifications"
  }

  if (type === "room_live") {
    const json = parseJsonContent(target.content)
    const slug = stringField(json, "room_slug")
    if (slug) return buildTradeRoomHref(slug, { live: true })
    if (target.room_id) {
      return `/community?room=${String(target.room_id)}&live=1`
    }
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