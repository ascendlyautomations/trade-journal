import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { parseLeadingCommentMention } from "@/lib/commentReplyUx"
import type { CommentNotificationKind } from "@/lib/notificationPreferences"
import { emitActivityNotification } from "@/lib/server/notifications/emit"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { isServerCommentNotificationAllowed } from "@/lib/serverNotificationPreferences"

type ResolvedComment = {
  sourceTable:
    | "comments"
    | "trade_comments"
    | "profile_post_comments"
    | "achievement_post_comments"
    | "reel_comments"
  targetTable: "posts" | "trades" | "profile_posts" | "achievement_posts" | "reels"
  targetColumn:
    | "post_id"
    | "trade_id"
    | "profile_post_id"
    | "achievement_post_id"
    | "reel_id"
  targetId: string
  content: string
  parentCommentId: string | null
}

const COMMENT_SOURCES: Array<{
  sourceTable: ResolvedComment["sourceTable"]
  targetTable: ResolvedComment["targetTable"]
  targetColumn: ResolvedComment["targetColumn"]
}> = [
  { sourceTable: "comments", targetTable: "posts", targetColumn: "post_id" },
  {
    sourceTable: "trade_comments",
    targetTable: "trades",
    targetColumn: "trade_id",
  },
  {
    sourceTable: "profile_post_comments",
    targetTable: "profile_posts",
    targetColumn: "profile_post_id",
  },
  {
    sourceTable: "achievement_post_comments",
    targetTable: "achievement_posts",
    targetColumn: "achievement_post_id",
  },
  {
    sourceTable: "reel_comments",
    targetTable: "reels",
    targetColumn: "reel_id",
  },
]

async function resolveAuthoredComment(
  commentId: string,
  userId: string
): Promise<ResolvedComment | null> {
  for (const source of COMMENT_SOURCES) {
    const { data, error } = await supabaseServiceRole
      .from(source.sourceTable)
      .select(`id, user_id, content, parent_comment_id, ${source.targetColumn}`)
      .eq("id", commentId)
      .eq("user_id", userId)
      .maybeSingle()
    if (error) {
      console.error(
        `[api/notifications/comment] ${source.sourceTable} lookup failed`,
        error
      )
      return null
    }
    const row = data as Record<string, unknown> | null
    const targetId = row?.[source.targetColumn]
    if (row && targetId) {
      return {
        ...source,
        targetId: String(targetId),
        content: String(row.content ?? "").trim().slice(0, 200),
        parentCommentId: row.parent_comment_id
          ? String(row.parent_comment_id)
          : null,
      }
    }
  }
  return null
}

async function commentParticipatedInTarget(
  comment: ResolvedComment,
  mentionedUserId: string
): Promise<boolean> {
  switch (comment.sourceTable) {
    case "comments": {
      const { data } = await supabaseServiceRole
        .from("comments")
        .select("id")
        .eq("post_id", comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      return Boolean(data)
    }
    case "trade_comments": {
      const { data } = await supabaseServiceRole
        .from("trade_comments")
        .select("id")
        .eq("trade_id", comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      return Boolean(data)
    }
    case "profile_post_comments": {
      const { data } = await supabaseServiceRole
        .from("profile_post_comments")
        .select("id")
        .eq("profile_post_id", comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      return Boolean(data)
    }
    case "achievement_post_comments": {
      const { data } = await supabaseServiceRole
        .from("achievement_post_comments")
        .select("id")
        .eq("achievement_post_id", comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      return Boolean(data)
    }
    case "reel_comments": {
      const { data } = await supabaseServiceRole
        .from("reel_comments")
        .select("id")
        .eq("reel_id", comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      return Boolean(data)
    }
  }
}

async function resolveCommentRecipients(
  comment: ResolvedComment,
  senderUserId: string
): Promise<Array<{ userId: string; kind: CommentNotificationKind }>> {
  const { data: owner } = await supabaseServiceRole
    .from(comment.targetTable)
    .select("user_id")
    .eq("id", comment.targetId)
    .maybeSingle()
  const ownerUserId = owner?.user_id ? String(owner.user_id) : ""

  if (!comment.parentCommentId) {
    return ownerUserId && ownerUserId !== senderUserId
      ? [{ userId: ownerUserId, kind: "comment" }]
      : []
  }

  const recipients = new Map<string, CommentNotificationKind>()
  const { data: parent } = await supabaseServiceRole
    .from(comment.sourceTable)
    .select(`user_id, ${comment.targetColumn}`)
    .eq("id", comment.parentCommentId)
    .maybeSingle()
  const parentRow = parent as Record<string, unknown> | null
  if (
    parentRow?.user_id &&
    String(parentRow[comment.targetColumn] ?? "") === comment.targetId &&
    String(parentRow.user_id) !== senderUserId
  ) {
    recipients.set(String(parentRow.user_id), "reply")
  }

  const { username } = parseLeadingCommentMention(comment.content)
  if (username) {
    const { data: mentionedProfile } = await supabaseServiceRole
      .from("profiles")
      .select("id, username")
      .eq("username", normalizeProfileUsername(username))
      .maybeSingle()
    const mentionedUserId = mentionedProfile?.id
      ? String(mentionedProfile.id)
      : ""

    if (mentionedUserId && mentionedUserId !== senderUserId) {
      const participated = await commentParticipatedInTarget(
        comment,
        mentionedUserId
      )
      if (participated) {
        // Leading `@parent` is the reply UX prefix — keep kind "reply".
        // Only upgrade to "mention" when the leading @ targets someone else.
        const existing = recipients.get(mentionedUserId)
        if (existing === "reply") {
          // parent author already notified as reply; do not reclassify
        } else if (mentionedUserId === ownerUserId) {
          recipients.set(
            mentionedUserId,
            existing ?? "reply"
          )
        } else {
          recipients.set(mentionedUserId, "mention")
        }
      }
    }
  }

  return [...recipients].map(([userId, kind]) => ({ userId, kind }))
}

export async function notifyComment(
  actorUserId: string,
  commentId: string
): Promise<
  | { ok: true; skipped?: boolean; deduplicated?: boolean; ids?: string[] }
  | { ok: false; error: string; status: number }
> {
  const trimmedCommentId = commentId?.trim()
  if (!trimmedCommentId) {
    return { ok: false, error: "Invalid notification payload", status: 400 }
  }

  // Recipient, content, parent, and target all come from the authenticated
  // author's persisted comment. Client-provided recipient/target fields are ignored.
  const resolvedComment = await resolveAuthoredComment(
    trimmedCommentId,
    actorUserId
  )
  if (!resolvedComment) {
    return { ok: false, error: "Comment not found", status: 404 }
  }

  const recipients = await resolveCommentRecipients(
    resolvedComment,
    actorUserId
  )
  if (!recipients.length) {
    return { ok: true, skipped: true }
  }

  const rows: Array<{
    user_id: string
    sender_id: string
    type: "comment"
    comment_id: string
    content: string
    [key: string]: unknown
  }> = []
  const kindByUser = new Map(
    recipients.map((r) => [r.userId, r.kind] as const)
  )

  for (const recipient of recipients) {
    const allowed = await isServerCommentNotificationAllowed(
      recipient.userId,
      recipient.kind,
      resolvedComment.targetColumn === "achievement_post_id"
    )
    if (!allowed) continue
    rows.push({
      user_id: recipient.userId,
      sender_id: actorUserId,
      type: "comment",
      comment_id: trimmedCommentId,
      content: resolvedComment.content,
      [resolvedComment.targetColumn]: resolvedComment.targetId,
    })
  }

  if (!rows.length) return { ok: true, skipped: true }

  let anyInserted = false
  let anyDeduped = false

  for (const row of rows) {
    const recipientUserId = String(row.user_id)
    const result = await emitActivityNotification({
      row: {
        user_id: recipientUserId,
        sender_id: actorUserId,
        type: "comment",
        comment_id: trimmedCommentId,
        content: resolvedComment.content,
        [resolvedComment.targetColumn]: resolvedComment.targetId,
      },
      push: {
        type: "comment",
        sender_id: actorUserId,
        comment_id: trimmedCommentId,
        content: resolvedComment.content,
        commentKind: kindByUser.get(recipientUserId) ?? "comment",
        prefsAlreadyChecked: true,
        [resolvedComment.targetColumn]: resolvedComment.targetId,
      },
      logLabel: "api/notifications/comment",
    })

    if (!result.ok) {
      return { ok: false, error: result.error, status: 500 }
    }
    if (result.deduplicated) anyDeduped = true
    if (result.inserted) anyInserted = true
  }

  if (!anyInserted && anyDeduped) {
    return { ok: true, deduplicated: true }
  }

  return { ok: true }
}
