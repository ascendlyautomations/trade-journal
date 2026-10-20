import type { ContentReportTargetType } from "@/lib/contentReports"
import { feedContentOwnerUserId } from "@/app/components/feed/feedPostHelpers"

export type ContentReportRequest = {
  targetType: ContentReportTargetType
  targetId: string
  reportedUserId: string | null
  subjectTitle: string
  blockUserId: string | null
}

function feedItemTarget(
  post: Record<string, unknown>
): { targetType: ContentReportTargetType; targetId: string } | null {
  const kind = String(post.feedKind ?? "trade")
  const id = String(post.id ?? "").trim()
  if (!id) return null
  switch (kind) {
    case "trade":
      return { targetType: "post", targetId: id }
    case "profile":
      return { targetType: "post", targetId: id }
    case "achievement":
      return { targetType: "achievement", targetId: id }
    case "reel":
      return { targetType: "reel", targetId: id }
    default:
      return { targetType: "post", targetId: id }
  }
}

function subjectLabelForFeedItem(post: Record<string, unknown>): string {
  const kind = String(post.feedKind ?? "trade")
  switch (kind) {
    case "trade":
      return "this trade"
    case "profile":
      return "this post"
    case "achievement":
      return "this achievement"
    case "reel":
      return "this clip"
    default:
      return "this content"
  }
}

/** Maps a feed timeline row to the same report targets as iOS FeedTimelineEntry. */
export function buildFeedItemContentReportRequest(
  post: unknown,
  viewerUserId: string | null | undefined
): ContentReportRequest | null {
  if (!post || typeof post !== "object") return null
  const row = post as Record<string, unknown>
  const ownerId = feedContentOwnerUserId(row)
  if (!ownerId || !viewerUserId || ownerId === viewerUserId) return null
  const target = feedItemTarget(row)
  if (!target) return null
  const username =
    row.profiles && typeof row.profiles === "object"
      ? String((row.profiles as { username?: unknown }).username ?? "").trim()
      : ""
  const subjectTitle = username ? `@${username.replace(/^@/, "")}` : subjectLabelForFeedItem(row)
  return {
    targetType: target.targetType,
    targetId: target.targetId,
    reportedUserId: ownerId,
    subjectTitle,
    blockUserId: ownerId,
  }
}

export function buildUserContentReportRequest(options: {
  userId: string
  displayName?: string | null
  viewerUserId: string | null | undefined
}): ContentReportRequest | null {
  const userId = String(options.userId ?? "").trim()
  if (!userId || !options.viewerUserId || userId === options.viewerUserId) {
    return null
  }
  const name = String(options.displayName ?? "").trim()
  return {
    targetType: "user",
    targetId: userId,
    reportedUserId: userId,
    subjectTitle: name || "this user",
    blockUserId: userId,
  }
}
