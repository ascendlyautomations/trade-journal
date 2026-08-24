import { after } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { emitActivityNotification } from "@/lib/server/notifications/emit"

export type LikeTarget =
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

type ContentOwnerTable =
  | "trades"
  | "posts"
  | "profile_posts"
  | "achievement_posts"
  | "reels"
  | "comments"
  | "trade_comments"
  | "profile_post_comments"
  | "achievement_post_comments"
  | "reel_comments"

function isContentOwnerTable(table: string): table is ContentOwnerTable {
  return (
    table === "trades" ||
    table === "posts" ||
    table === "profile_posts" ||
    table === "achievement_posts" ||
    table === "reels" ||
    COMMENT_SOURCES.has(table)
  )
}

async function resolveContentOwner(
  table: string,
  id: string
): Promise<string | null> {
  if (!isContentOwnerTable(table)) return null
  const { data, error } = await supabaseServiceRole
    .from(table)
    .select("user_id")
    .eq("id", id)
    .maybeSingle()
  if (error || !data?.user_id) return null
  return String(data.user_id)
}

export async function resolveLikeTarget(
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

export async function notifyLike(
  actorUserId: string,
  target: LikeTarget
): Promise<
  | { ok: true; skipped?: boolean; deduplicated?: boolean }
  | { ok: false; error: string; status: number }
> {
  const resolved = target ? await resolveLikeTarget(target, actorUserId) : null
  if (!resolved) {
    return { ok: false, error: "Like not found", status: 400 }
  }
  if (!resolved.likeExists) {
    return { ok: false, error: "Like not found", status: 404 }
  }
  if (resolved.recipientUserId === actorUserId) {
    return { ok: true, skipped: true }
  }

  const result = await emitActivityNotification({
    row: {
      user_id: resolved.recipientUserId,
      sender_id: actorUserId,
      type: "like",
      ...resolved.notificationTarget,
    },
    push: {
      type: "like",
      sender_id: actorUserId,
      prefsAlreadyChecked: true,
      ...resolved.notificationTarget,
    },
    logLabel: "api/notifications/like",
  })

  if (!result.ok) {
    return { ok: false, error: result.error, status: 500 }
  }

  if (result.inserted && target.kind !== "comment") {
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
      const ownerUserId = resolved.recipientUserId
      after(async () => {
        const { notify } = await import(
          "@/lib/server/notifications/NotificationService"
        )
        await notify({
          type: "like_milestone",
          ownerUserId,
          actorUserId,
          entity,
        })
      })
    }
  }

  return { ok: true, deduplicated: result.deduplicated }
}
