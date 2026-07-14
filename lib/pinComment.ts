import type { PostgrestError, SupabaseClient } from "@supabase/supabase-js"

export type CommentPinKind =
  | "feed"
  | "trade"
  | "profile_post"
  | "achievement_post"
  | "reel"

export function canPinComment(params: {
  viewerUserId: string | null | undefined
  contentOwnerUserId: string | null | undefined
}): boolean {
  const viewer = params.viewerUserId != null ? String(params.viewerUserId) : ""
  const owner =
    params.contentOwnerUserId != null ? String(params.contentOwnerUserId) : ""
  return Boolean(viewer && owner && viewer === owner)
}

export function isCommentPinned(comment: {
  pinned?: boolean | null
}): boolean {
  return comment.pinned === true
}

/** Local optimistic / realtime apply: one pinned top-level comment max. */
export function applyPinnedCommentState<
  T extends {
    id: string | number
    pinned?: boolean | null
    parent_comment_id?: string | null
  },
>(comments: T[], commentId: string, pinned: boolean): T[] {
  const targetId = String(commentId)
  return comments.map((comment) => {
    const id = String(comment.id)
    if (id === targetId) {
      return { ...comment, pinned }
    }
    if (pinned && comment.pinned === true && !comment.parent_comment_id) {
      return { ...comment, pinned: false }
    }
    return comment
  })
}

type PinParams = {
  commentId: string
  pinned: boolean
  /** Must be a top-level comment. */
  parentCommentId?: string | null
}

async function updatePinned(
  supabase: SupabaseClient,
  table: string,
  params: PinParams
): Promise<{ error: PostgrestError | Error | null }> {
  if (params.parentCommentId) {
    return {
      error: new Error("Only top-level comments can be pinned."),
    }
  }

  const { error } = await supabase
    .from(table)
    .update({ pinned: params.pinned })
    .eq("id", params.commentId)

  return { error: error ?? null }
}

export async function pinFeedComment(
  supabase: SupabaseClient,
  params: PinParams
) {
  return updatePinned(supabase, "comments", params)
}

export async function pinTradeComment(
  supabase: SupabaseClient,
  params: PinParams
) {
  return updatePinned(supabase, "trade_comments", params)
}

export async function pinProfilePostComment(
  supabase: SupabaseClient,
  params: PinParams
) {
  return updatePinned(supabase, "profile_post_comments", params)
}

export async function pinAchievementPostComment(
  supabase: SupabaseClient,
  params: PinParams
) {
  return updatePinned(supabase, "achievement_post_comments", params)
}

export async function pinReelComment(
  supabase: SupabaseClient,
  params: PinParams
) {
  return updatePinned(supabase, "reel_comments", params)
}

export async function pinCommentByKind(
  supabase: SupabaseClient,
  kind: CommentPinKind,
  params: PinParams
) {
  switch (kind) {
    case "feed":
      return pinFeedComment(supabase, params)
    case "trade":
      return pinTradeComment(supabase, params)
    case "profile_post":
      return pinProfilePostComment(supabase, params)
    case "achievement_post":
      return pinAchievementPostComment(supabase, params)
    case "reel":
      return pinReelComment(supabase, params)
    default:
      return { error: new Error(`Unknown comment pin kind: ${kind}`) }
  }
}

/** Infer pin table + state key from a comment row. */
export function resolveCommentPinTarget(comment: {
  profile_post_id?: string | null
  achievement_post_id?: string | null
  reel_id?: string | null
  trade_id?: string | null
  post_id?: string | null
}): { kind: CommentPinKind; stateKey: string } | null {
  const profilePostId =
    comment.profile_post_id != null ? String(comment.profile_post_id) : ""
  if (profilePostId) {
    return { kind: "profile_post", stateKey: profilePostId }
  }
  const achievementPostId =
    comment.achievement_post_id != null
      ? String(comment.achievement_post_id)
      : ""
  if (achievementPostId) {
    return { kind: "achievement_post", stateKey: achievementPostId }
  }
  const reelId = comment.reel_id != null ? String(comment.reel_id) : ""
  if (reelId) {
    return { kind: "reel", stateKey: reelId }
  }
  const tradeId = comment.trade_id != null ? String(comment.trade_id) : ""
  if (tradeId) {
    return { kind: "trade", stateKey: tradeId }
  }
  const postId = comment.post_id != null ? String(comment.post_id) : ""
  if (postId) {
    return { kind: "feed", stateKey: postId }
  }
  return null
}
