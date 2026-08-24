import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { notify } from "@/lib/server/notifications/NotificationService"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let commentId: string | undefined
  try {
    const body = (await req.json()) as { commentId?: string }
    commentId = body.commentId?.trim()
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  if (!commentId) {
    return Response.json({ error: "Invalid commentId" }, { status: 400 })
  }

  const result = await notify({
    type: "comment",
    actorUserId: user.id,
    commentId,
  })

  if (!result.ok) {
    return Response.json(
      { error: result.error ?? "Comment notify failed" },
      { status: result.status ?? 500 }
    )
  }

  return Response.json({
    ok: true,
    skipped: result.skipped,
    deduplicated: result.deduplicated,
  })
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
  const target = {
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

  const { invalidateAppIconBadgeCache } = await import(
    "@/lib/server/push/badgeService"
  )

  if (commentId) {
    const { data: affected } = await supabaseServiceRole
      .from("notifications")
      .select("user_id")
      .eq("type", "comment")
      .eq("comment_id", commentId)
      .eq("sender_id", user.id)

    const { error: byCommentIdErr } = await supabaseServiceRole
      .from("notifications")
      .delete()
      .eq("type", "comment")
      .eq("comment_id", commentId)
      .eq("sender_id", user.id)

    if (byCommentIdErr) {
      console.error(
        "[api/notifications/comment] delete by comment_id failed",
        byCommentIdErr
      )
      return Response.json({ error: byCommentIdErr.message }, { status: 500 })
    }

    for (const row of affected ?? []) {
      if (row.user_id) invalidateAppIconBadgeCache(String(row.user_id))
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
      legacyQuery = legacyQuery.eq(
        "achievement_post_id",
        target.achievementPostId
      )
    } else if (target.reelId) {
      legacyQuery = legacyQuery.eq("reel_id", target.reelId)
    } else if (target.postId) {
      legacyQuery = legacyQuery.eq("post_id", target.postId)
    } else if (target.tradeId) {
      legacyQuery = legacyQuery.eq("trade_id", target.tradeId)
    }

    const { error: legacyErr } = await legacyQuery
    if (legacyErr) {
      console.error(
        "[api/notifications/comment] legacy delete failed",
        legacyErr
      )
      return Response.json({ error: legacyErr.message }, { status: 500 })
    }
    // Legacy deletes may hit unknown recipients — drop full cache.
    invalidateAppIconBadgeCache()
  }

  return Response.json({ ok: true })
}
