import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isServerCommentNotificationAllowed } from "@/lib/serverNotificationPreferences"
import { resolveCommentNotificationRecipient } from "@/lib/server/resolveCommentNotificationRecipient"
import type { CommentNotificationKind } from "@/lib/notificationPreferences"

type CommentTargetBody = {
  postId?: string | null
  tradeId?: string | null
  profilePostId?: string | null
  achievementPostId?: string | null
  reelId?: string | null
}

async function commentAuthoredByUser(
  commentId: string,
  userId: string
): Promise<boolean> {
  const tables = [
    { table: "comments" as const, column: "id" },
    { table: "trade_comments" as const, column: "id" },
    { table: "profile_post_comments" as const, column: "id" },
    { table: "achievement_post_comments" as const, column: "id" },
    { table: "reel_comments" as const, column: "id" },
  ]

  for (const { table } of tables) {
    const { data, error } = await supabaseServiceRole
      .from(table)
      .select("id")
      .eq("id", commentId)
      .eq("user_id", userId)
      .maybeSingle()

    if (error) {
      console.error(`[api/notifications/comment] ${table} lookup failed`, error)
      return false
    }
    if (data) return true
  }

  return false
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

  const recipientUserIdFromClient = body.recipientUserId?.trim()
  const commentId = body.commentId?.trim()
  const content = body.content?.trim().slice(0, 200) ?? ""

  if (!commentId) {
    return Response.json({ error: "Invalid notification payload" }, { status: 400 })
  }

  const authored = await commentAuthoredByUser(commentId, user.id)
  if (!authored) {
    return Response.json({ error: "Comment not found" }, { status: 404 })
  }

  const hasTarget =
    body.profilePostId ||
    body.achievementPostId ||
    body.reelId ||
    body.postId ||
    body.tradeId

  if (!hasTarget) {
    return Response.json({ error: "Missing comment target" }, { status: 400 })
  }

  const recipientUserId = await resolveCommentNotificationRecipient({
    postId: body.postId,
    tradeId: body.tradeId,
    profilePostId: body.profilePostId,
    achievementPostId: body.achievementPostId,
    reelId: body.reelId,
  })

  if (!recipientUserId || recipientUserId === user.id) {
    return Response.json({ error: "Invalid notification recipient" }, { status: 400 })
  }

  if (
    recipientUserIdFromClient &&
    recipientUserIdFromClient !== recipientUserId
  ) {
    console.warn("[api/notifications/comment] client recipient mismatch", {
      client: recipientUserIdFromClient,
      resolved: recipientUserId,
    })
  }

  const isAchievement = Boolean(body.achievementPostId)
  const isReel = Boolean(body.reelId)
  const kind: CommentNotificationKind = body.kind ?? "comment"
  const allowed = await isServerCommentNotificationAllowed(
    recipientUserId,
    kind,
    isAchievement
  )
  if (!allowed) {
    return Response.json({ ok: true, skipped: true })
  }

  const insertRow: Record<string, unknown> = {
    user_id: recipientUserId,
    sender_id: user.id,
    type: "comment",
    comment_id: commentId,
    content,
  }

  if (body.profilePostId) {
    insertRow.profile_post_id = body.profilePostId
  } else if (body.achievementPostId) {
    insertRow.achievement_post_id = body.achievementPostId
  } else if (body.reelId) {
    insertRow.reel_id = body.reelId
  } else if (body.postId) {
    insertRow.post_id = body.postId
    if (body.tradeId) insertRow.trade_id = body.tradeId
  } else if (body.tradeId) {
    insertRow.trade_id = body.tradeId
  } else {
    return Response.json({ error: "Missing comment target" }, { status: 400 })
  }

  const { data, error: insertErr } = await supabaseServiceRole
    .from("notifications")
    .insert(insertRow)
    .select("id, comment_id")
    .single()

  if (insertErr) {
    if (insertErr.code === "23505") {
      return Response.json({ ok: true, deduplicated: true })
    }
    console.error("[api/notifications/comment] insert failed", insertErr)
    return Response.json({ error: insertErr.message }, { status: 500 })
  }

  if (!data?.comment_id || String(data.comment_id) !== commentId) {
    console.error("[api/notifications/comment] comment_id not persisted", {
      expected: commentId,
      row: data,
    })
    return Response.json({ error: "comment_id not persisted" }, { status: 500 })
  }

  return Response.json({ ok: true, id: data.id })
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
