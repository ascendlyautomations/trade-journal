import type { SupabaseClient } from "@supabase/supabase-js"
import { ensureCommentNotificationsForInsert } from "./commentNotifications"
import { ensureLikeNotification } from "./likeNotifications"

export const PROFILE_POST_COMMENT_CORE_SELECT =
  "id, profile_post_id, user_id, content, created_at, profiles(username, avatar_url)"

export const PROFILE_POST_COMMENTS_SELECT =
  `${PROFILE_POST_COMMENT_CORE_SELECT}, parent_comment_id`

export const PROFILE_POST_COMMENT_INSERT_SELECT = PROFILE_POST_COMMENT_CORE_SELECT

export function isProfileFeedPost(post: { feedKind?: string } | null | undefined): boolean {
  return post?.feedKind === "profile"
}

export function profilePostOwnerUserId(post: {
  user_id?: string | null
}): string | null {
  const id = post.user_id
  if (id == null || String(id).trim() === "") return null
  return String(id)
}

function isMissingParentCommentIdColumn(error: {
  code?: string
  message?: string
} | null): boolean {
  if (!error) return false
  if (error.code === "PGRST204") return true
  const msg = (error.message ?? "").toLowerCase()
  return msg.includes("parent_comment_id")
}

export async function queryProfilePostComments<T extends { data: unknown; error: unknown }>(
  run: (select: string) => Promise<T>
): Promise<T> {
  const full = await run(PROFILE_POST_COMMENTS_SELECT)
  if (
    !full.error ||
    !isMissingParentCommentIdColumn(full.error as { code?: string; message?: string })
  ) {
    return full
  }
  return run(PROFILE_POST_COMMENT_CORE_SELECT)
}

export function withInsertedProfilePostParentCommentId<T extends Record<string, unknown>>(
  row: T,
  parentCommentId?: string | null
): T & { parent_comment_id?: string | null } {
  if (!parentCommentId) return row
  return { ...row, parent_comment_id: parentCommentId }
}

export async function insertProfilePostLikeNotification(
  supabase: SupabaseClient,
  params: {
    profilePostId: string
    ownerUserId: string
    senderUserId: string
  }
) {
  await ensureLikeNotification(supabase, {
    recipientUserId: params.ownerUserId,
    senderUserId: params.senderUserId,
    target: { kind: "profile_post", profilePostId: params.profilePostId },
  })
}

export async function insertProfilePostCommentNotifications(
  supabase: SupabaseClient,
  params: {
    profilePostId: string
    commentId: string
    ownerUserId: string
    senderUserId: string
    content: string
    parentCommentId?: string | null
    existingComments?: Array<{ id: string; user_id: string }>
  }
) {
  await ensureCommentNotificationsForInsert(supabase, {
    commentId: params.commentId,
    senderUserId: params.senderUserId,
    content: params.content,
    target: { kind: "profile_post", profilePostId: params.profilePostId },
    ownerUserId: params.ownerUserId,
    parentCommentId: params.parentCommentId,
    existingComments: params.existingComments,
  })
}
