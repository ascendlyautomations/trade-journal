import type { SupabaseClient } from "@supabase/supabase-js"

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

function dispatchNotificationRefresh() {
  window.dispatchEvent(new CustomEvent("notification-update"))
  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
}

export async function insertProfilePostLikeNotification(
  supabase: SupabaseClient,
  params: {
    profilePostId: string
    ownerUserId: string
    senderUserId: string
  }
) {
  if (params.ownerUserId === params.senderUserId) return

  const { error } = await supabase.from("notifications").insert({
    user_id: params.ownerUserId,
    sender_id: params.senderUserId,
    type: "like",
    profile_post_id: params.profilePostId,
  })

  if (error) {
    console.error("Profile post like notification error:", error.message, error)
    return
  }

  dispatchNotificationRefresh()
}

export async function insertProfilePostCommentNotifications(
  supabase: SupabaseClient,
  params: {
    profilePostId: string
    ownerUserId: string
    senderUserId: string
    content: string
    parentCommentId?: string | null
    existingComments?: Array<{ id: string; user_id: string }>
  }
) {
  const receivers = new Set<string>()
  const snippet = params.content.trim().slice(0, 200)

  if (params.parentCommentId) {
    const parent = params.existingComments?.find(
      (c) => String(c.id) === String(params.parentCommentId)
    )
    const parentUserId =
      parent?.user_id != null ? String(parent.user_id).trim() : ""
    if (parentUserId && parentUserId !== params.senderUserId) {
      receivers.add(parentUserId)
    }
  } else if (
    params.ownerUserId &&
    params.ownerUserId !== params.senderUserId
  ) {
    receivers.add(params.ownerUserId)
  }

  for (const receiverId of receivers) {
    const { error } = await supabase.from("notifications").insert({
      user_id: receiverId,
      sender_id: params.senderUserId,
      type: "comment",
      profile_post_id: params.profilePostId,
      content: snippet,
    })

    if (error) {
      console.error("Profile post comment notification error:", error.message, error)
    }
  }

  if (receivers.size > 0) {
    dispatchNotificationRefresh()
  }
}
