import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isServerCommentNotificationAllowed } from "@/lib/serverNotificationPreferences"
import type { CommentNotificationKind } from "@/lib/notificationPreferences"
import { parseLeadingCommentMention } from "@/lib/commentReplyUx"
import { normalizeProfileUsername } from "@/lib/profileUsername"

type CommentTargetBody = {
  postId?: string | null
  tradeId?: string | null
  profilePostId?: string | null
  achievementPostId?: string | null
  reelId?: string | null
}

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
      const { data: participated } = await supabaseServiceRole
        .from(comment.sourceTable)
        .select("id")
        .eq(comment.targetColumn, comment.targetId)
        .eq("user_id", mentionedUserId)
        .limit(1)
        .maybeSingle()
      if (participated) {
        recipients.set(
          mentionedUserId,
          mentionedUserId !== ownerUserId ? "mention" : recipients.get(mentionedUserId) ?? "reply"
        )
      }
    }
  }

  return [...recipients].map(([userId, kind]) => ({ userId, kind }))
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: {
    recipientUserId?: string
    commentId?: string
    content?: string
    postId?: string | null
    tradeId?: string | null
    profilePostId?: string | null
    achievementPostId?: string | null
    reelId?: string | null
    kind?: CommentNotificationKind
  }
  try {
    body = (await req.json()) as typeof body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const commentId = body.commentId?.trim()

  if (!commentId) {
    return Response.json({ error: "Invalid notification payload" }, { status: 400 })
  }

  // Recipient, content, parent, and target all come from the authenticated
  // author's persisted comment. Client-provided recipient/target fields are ignored.
  const resolvedComment = await resolveAuthoredComment(commentId, user.id)
  if (!resolvedComment) {
    return Response.json({ error: "Comment not found" }, { status: 404 })
  }

  const recipients = await resolveCommentRecipients(resolvedComment, user.id)
  if (!recipients.length) {
    return Response.json({ ok: true, skipped: true })
  }

  const rows: Record<string, unknown>[] = []
  for (const recipient of recipients) {
    const allowed = await isServerCommentNotificationAllowed(
      recipient.userId,
      recipient.kind,
      resolvedComment.targetColumn === "achievement_post_id"
    )
    if (!allowed) continue
    rows.push({
      user_id: recipient.userId,
      sender_id: user.id,
      type: "comment",
      comment_id: commentId,
      content: resolvedComment.content,
      [resolvedComment.targetColumn]: resolvedComment.targetId,
    })
  }

  if (!rows.length) return Response.json({ ok: true, skipped: true })

  const { data, error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert(rows)
    .select("id, comment_id")

  if (insertErr) {
    if (insertErr.code === "23505") {
      return Response.json({ ok: true, deduplicated: true })
    }
    console.error("[api/notifications/comment] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  if (
    !data?.length ||
    data.some((row) => !row.comment_id || String(row.comment_id) !== commentId)
  ) {
    console.error("[api/notifications/comment] comment_id not persisted", {
      expected: commentId,
      row: data,
    })
    return Response.json({ error: "comment_id not persisted" }, { status: 500 })
  }

  const { scheduleIosPushDelivery } = await import(
    "@/lib/server/push/deliverPushNotification"
  )
  const kindByUser = new Map(
    recipients.map((r) => [r.userId, r.kind] as const)
  )
  for (const row of rows) {
    const recipientUserId = String(row.user_id)
    scheduleIosPushDelivery({
      recipientUserId,
      type: "comment",
      sender_id: user.id,
      comment_id: commentId,
      content: resolvedComment.content,
      commentKind: kindByUser.get(recipientUserId) ?? "comment",
      prefsAlreadyChecked: true,
      [resolvedComment.targetColumn]: resolvedComment.targetId,
    })
  }

  return Response.json({ ok: true, ids: data.map((row) => row.id) })
}

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: {
    commentId?: string
    content?: string
    postId?: string | null
    tradeId?: string | null
    profilePostId?: string | null
    achievementPostId?: string | null
    reelId?: string | null
  }
  try {
    body = (await req.json()) as typeof body
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const commentId = body.commentId?.trim()
  const snippet = body.content?.trim().slice(0, 200) ?? ""
  const target: CommentTargetBody = {
    postId: body.postId,
    tradeId: body.tradeId,
    profilePostId: body.profilePostId,
    achievementPostId: body.achievementPostId,
    reelId: body.reelId,
  }
  const hasLegacyTarget = Boolean(
    snippet &&
      (target.postId ||
        target.tradeId ||
        target.profilePostId ||
        target.achievementPostId ||
        target.reelId)
  )

  if (!commentId && !hasLegacyTarget) {
    return Response.json({ error: "Nothing to delete" }, { status: 400 })
  }

  if (commentId) {
    const { error: byCommentIdErr } = await supabaseServiceRole
      .from("notifications")
      .delete()
      .eq("type", "comment")
      .eq("comment_id", commentId)
      .eq("sender_id", user.id)

    if (byCommentIdErr) {
      console.error("[api/notifications/comment] delete by comment_id failed", byCommentIdErr)
      return Response.json({ error: byCommentIdErr.message }, { status: 500 })
    }
  }

  if (hasLegacyTarget) {
    let legacyQuery = supabaseServiceRole
      .from("notifications")
      .delete()
      .eq("type", "comment")
      .eq("sender_id", user.id)
      .is("comment_id", null)
      .eq("content", snippet)

    if (target.profilePostId) {
      legacyQuery = legacyQuery.eq("profile_post_id", target.profilePostId)
    } else if (target.achievementPostId) {
      legacyQuery = legacyQuery.eq("achievement_post_id", target.achievementPostId)
    } else if (target.reelId) {
      legacyQuery = legacyQuery.eq("reel_id", target.reelId)
    } else if (target.postId) {
      legacyQuery = legacyQuery.eq("post_id", target.postId)
    } else if (target.tradeId) {
      legacyQuery = legacyQuery.eq("trade_id", target.tradeId)
    }

    const { error: legacyErr } = await legacyQuery
    if (legacyErr) {
      console.error("[api/notifications/comment] legacy delete failed", legacyErr)
      return Response.json({ error: legacyErr.message }, { status: 500 })
    }
  }

  return Response.json({ ok: true })
}
