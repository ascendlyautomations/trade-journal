import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type LikeTarget =
  | { kind: "trade"; tradeId: string }
  | { kind: "post"; postId: string; tradeId?: string | null }
  | { kind: "profile_post"; profilePostId: string }
  | { kind: "achievement_post"; achievementPostId: string }
  | { kind: "reel"; reelId: string }
  | {
      kind: "comment"
      commentId: string
      commentSource?: string | null
      postId?: string | null
      tradeId?: string | null
      profilePostId?: string | null
      achievementPostId?: string | null
      reelId?: string | null
    }

type ResolvedLike = {
  recipientUserId: string
  notificationTarget: Record<string, string | null>
  likeExists: boolean
}

const COMMENT_SOURCES = new Set([
  "comments",
  "trade_comments",
  "profile_post_comments",
  "achievement_post_comments",
  "reel_comments",
])

async function resolveContentOwner(
  table: string,
  id: string
): Promise<string | null> {
  const { data, error } = await supabaseServiceRole
    .from(table)
    .select("user_id")
    .eq("id", id)
    .maybeSingle()
  if (error || !data?.user_id) return null
  return String(data.user_id)
}

async function resolveLike(
  target: LikeTarget,
  actorUserId: string
): Promise<ResolvedLike | null> {
  if (target.kind === "trade" && target.tradeId) {
    const [recipientUserId, like] = await Promise.all([
      resolveContentOwner("trades", target.tradeId),
      supabaseServiceRole
        .from("trade_likes")
        .select("trade_id")
        .eq("trade_id", target.tradeId)
        .eq("user_id", actorUserId)
        .maybeSingle(),
    ])
    return recipientUserId
      ? {
          recipientUserId,
          notificationTarget: { trade_id: target.tradeId },
          likeExists: Boolean(like.data),
        }
      : null
  }

  if (target.kind === "post" && target.postId) {
    const [recipientUserId, like] = await Promise.all([
      resolveContentOwner("posts", target.postId),
      supabaseServiceRole
        .from("likes")
        .select("post_id")
        .eq("post_id", target.postId)
        .eq("user_id", actorUserId)
        .maybeSingle(),
    ])
    return recipientUserId
      ? {
          recipientUserId,
          notificationTarget: {
            post_id: target.postId,
            trade_id: target.tradeId ?? null,
          },
          likeExists: Boolean(like.data),
        }
      : null
  }

  if (target.kind === "profile_post" && target.profilePostId) {
    const [recipientUserId, like] = await Promise.all([
      resolveContentOwner("profile_posts", target.profilePostId),
      supabaseServiceRole
        .from("profile_post_likes")
        .select("profile_post_id")
        .eq("profile_post_id", target.profilePostId)
        .eq("user_id", actorUserId)
        .maybeSingle(),
    ])
    return recipientUserId
      ? {
          recipientUserId,
          notificationTarget: { profile_post_id: target.profilePostId },
          likeExists: Boolean(like.data),
        }
      : null
  }

  if (target.kind === "achievement_post" && target.achievementPostId) {
    const [recipientUserId, like] = await Promise.all([
      resolveContentOwner("achievement_posts", target.achievementPostId),
      supabaseServiceRole
        .from("achievement_post_likes")
        .select("achievement_post_id")
        .eq("achievement_post_id", target.achievementPostId)
        .eq("user_id", actorUserId)
        .maybeSingle(),
    ])
    return recipientUserId
      ? {
          recipientUserId,
          notificationTarget: {
            achievement_post_id: target.achievementPostId,
          },
          likeExists: Boolean(like.data),
        }
      : null
  }

  if (target.kind === "reel" && target.reelId) {
    const [recipientUserId, like] = await Promise.all([
      resolveContentOwner("reels", target.reelId),
      supabaseServiceRole
        .from("reel_likes")
        .select("reel_id")
        .eq("reel_id", target.reelId)
        .eq("user_id", actorUserId)
        .maybeSingle(),
    ])
    return recipientUserId
      ? {
          recipientUserId,
          notificationTarget: { reel_id: target.reelId },
          likeExists: Boolean(like.data),
        }
      : null
  }

  if (target.kind !== "comment" || !target.commentId) return null
  const source = String(target.commentSource ?? "")
  if (!COMMENT_SOURCES.has(source)) return null

  const [recipientUserId, like] = await Promise.all([
    resolveContentOwner(source, target.commentId),
    supabaseServiceRole
      .from("comment_likes")
      .select("comment_id")
      .eq("comment_source", source)
      .eq("comment_id", target.commentId)
      .eq("user_id", actorUserId)
      .maybeSingle(),
  ])
  return recipientUserId
    ? {
        recipientUserId,
        notificationTarget: {
          comment_id: target.commentId,
          post_id: target.postId ?? null,
          trade_id: target.tradeId ?? null,
          profile_post_id: target.profilePostId ?? null,
          achievement_post_id: target.achievementPostId ?? null,
          reel_id: target.reelId ?? null,
        },
        likeExists: Boolean(like.data),
      }
    : null
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let target: LikeTarget
  try {
    target = ((await req.json()) as { target?: LikeTarget }).target as LikeTarget
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const resolved = target ? await resolveLike(target, user.id) : null
  if (!resolved?.likeExists) {
    return Response.json({ error: "Like not found" }, { status: 404 })
  }
  if (resolved.recipientUserId === user.id) {
    return Response.json({ ok: true, skipped: true })
  }

  const { error } = await supabaseServiceRole.from("notifications").insert({
    user_id: resolved.recipientUserId,
    sender_id: user.id,
    type: "like",
    ...resolved.notificationTarget,
  })
  if (error && error.code !== "23505") {
    console.error("[api/notifications/like] insert failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }
  if (!error) {
    const { scheduleIosPushDelivery } = await import(
      "@/lib/server/push/deliverPushNotification"
    )
    scheduleIosPushDelivery({
      recipientUserId: resolved.recipientUserId,
      type: "like",
      sender_id: user.id,
      prefsAlreadyChecked: true,
      ...resolved.notificationTarget,
    })

    // Milestone pushes for public content likes only (never comments).
    if (target.kind !== "comment") {
      const { maybeNotifyLikeMilestone } = await import(
        "@/lib/server/push/likeMilestones"
      )
      const entity =
        target.kind === "trade"
          ? { kind: "trade" as const, id: target.tradeId }
          : target.kind === "post"
            ? { kind: "post" as const, id: target.postId }
            : target.kind === "profile_post"
              ? { kind: "profile_post" as const, id: target.profilePostId }
              : target.kind === "achievement_post"
                ? {
                    kind: "achievement_post" as const,
                    id: target.achievementPostId,
                  }
                : target.kind === "reel"
                  ? { kind: "reel" as const, id: target.reelId }
                  : null
      if (entity?.id) {
        void maybeNotifyLikeMilestone({
          ownerUserId: resolved.recipientUserId,
          actorUserId: user.id,
          entity,
        })
      }
    }
  }
  return Response.json({ ok: true, deduplicated: error?.code === "23505" })
}

export async function DELETE(req: Request) {
  const user = await getRouteUser(req)
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 })

  let target: LikeTarget
  try {
    target = ((await req.json()) as { target?: LikeTarget }).target as LikeTarget
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { status: 400 })
  }

  const resolved = target ? await resolveLike(target, user.id) : null
  if (!resolved) {
    return Response.json({ error: "Target not found" }, { status: 404 })
  }

  let query = supabaseServiceRole
    .from("notifications")
    .delete()
    .eq("type", "like")
    .eq("user_id", resolved.recipientUserId)
    .eq("sender_id", user.id)

  for (const [column, value] of Object.entries(resolved.notificationTarget)) {
    if (value) query = query.eq(column, value)
  }

  const { error } = await query
  if (error) {
    console.error("[api/notifications/like] delete failed", error)
    return Response.json({ error: error.message }, { status: 500 })
  }
  return Response.json({ ok: true })
}
