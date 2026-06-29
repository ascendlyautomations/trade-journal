import type { SupabaseClient } from "@supabase/supabase-js"
import { parseLeadingCommentMention } from "@/lib/commentReplyUx"
import type { CommentNotificationKind } from "@/lib/notificationPreferences"
import { normalizeProfileUsername } from "@/lib/profileUsername"

async function authFetch(
  supabase: SupabaseClient,
  url: string,
  init: RequestInit
): Promise<Response | null> {
  const {
    data: { session },
  } = await supabase.auth.getSession()
  const accessToken = session?.access_token
  if (!accessToken) {
    console.error("[comment-notifications] skipped: no auth session")
    return null
  }

  return fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${accessToken}`,
      ...(init.headers as Record<string, string> | undefined),
    },
  })
}

function targetToApiFields(target: CommentNotificationTarget) {
  if (target.kind === "post") {
    return { postId: target.postId, tradeId: target.tradeId ?? null }
  }
  if (target.kind === "trade") {
    return { tradeId: target.tradeId }
  }
  if (target.kind === "profile_post") {
    return { profilePostId: target.profilePostId }
  }
  if (target.kind === "achievement_post") {
    return { achievementPostId: target.achievementPostId }
  }
  return { reelId: target.reelId }
}

export type CommentNotificationTarget =
  | { kind: "post"; postId: string; tradeId?: string | null }
  | { kind: "trade"; tradeId: string }
  | { kind: "profile_post"; profilePostId: string }
  | { kind: "achievement_post"; achievementPostId: string }
  | { kind: "reel"; reelId: string }

type CommentNotificationParams = {
  recipientUserId: string
  senderUserId: string
  commentId: string
  content: string
  target: CommentNotificationTarget
  kind?: CommentNotificationKind
}

function dispatchNotificationRefresh() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent("notification-update"))
  window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
}

export function resolveCommentNotificationRecipients(params: {
  senderUserId: string
  ownerUserId?: string | null
  parentCommentId?: string | null
  content?: string | null
  existingComments?: Array<{
    id: string
    user_id: string
    profiles?: { username?: string | null } | null
  }>
}): string[] {
  const receivers = new Set<string>()
  const senderId = String(params.senderUserId).trim()

  if (params.parentCommentId) {
    const parent = params.existingComments?.find(
      (c) => String(c.id) === String(params.parentCommentId)
    )
    const parentUserId =
      parent?.user_id != null ? String(parent.user_id).trim() : ""
    if (parentUserId && parentUserId !== senderId) {
      receivers.add(parentUserId)
    }

    const { username: mentionedUsername } = parseLeadingCommentMention(
      params.content ?? ""
    )
    if (mentionedUsername && params.existingComments?.length) {
      const mentioned = params.existingComments.find(
        (c) =>
          normalizeProfileUsername(c.profiles?.username ?? "") ===
          mentionedUsername
      )
      const mentionedUserId =
        mentioned?.user_id != null ? String(mentioned.user_id).trim() : ""
      if (mentionedUserId && mentionedUserId !== senderId) {
        receivers.add(mentionedUserId)
      }
    }

    return Array.from(receivers)
  }

  const ownerId =
    params.ownerUserId != null ? String(params.ownerUserId).trim() : ""
  if (ownerId && ownerId !== senderId) {
    receivers.add(ownerId)
  }
  return Array.from(receivers)
}

export function buildCommentNotificationInsertPayload(
  params: CommentNotificationParams
): Record<string, unknown> {
  const commentId = String(params.commentId ?? "").trim()
  if (!commentId) {
    throw new Error("comment notification requires commentId")
  }

  const snippet = params.content.trim().slice(0, 200)
  const base = {
    user_id: params.recipientUserId,
    sender_id: params.senderUserId,
    type: "comment" as const,
    comment_id: commentId,
    content: snippet,
  }

  if (params.target.kind === "post") {
    return {
      ...base,
      post_id: params.target.postId,
      trade_id: params.target.tradeId ?? null,
    }
  }
  if (params.target.kind === "trade") {
    return { ...base, trade_id: params.target.tradeId }
  }
  if (params.target.kind === "profile_post") {
    return { ...base, profile_post_id: params.target.profilePostId }
  }
  if (params.target.kind === "achievement_post") {
    return { ...base, achievement_post_id: params.target.achievementPostId }
  }
  return { ...base, reel_id: params.target.reelId }
}

/** Create exactly one comment notification per recipient for this comment. */
export async function ensureCommentNotification(
  supabase: SupabaseClient,
  params: CommentNotificationParams
): Promise<void> {
  if (params.recipientUserId === params.senderUserId) return

  const commentId = String(params.commentId ?? "").trim()
  if (!commentId) {
    console.error("Comment notification skipped: missing commentId", params)
    return
  }

  const res = await authFetch(supabase, "/api/notifications/comment", {
    method: "POST",
    body: JSON.stringify({
      recipientUserId: params.recipientUserId,
      commentId,
      content: params.content,
      kind: params.kind ?? "comment",
      ...targetToApiFields(params.target),
    }),
  })

  if (!res) return

  if (!res.ok) {
    const body = await res.text()
    if (body.includes("deduplicated") || res.status === 409) {
      dispatchNotificationRefresh()
      return
    }
    console.error("Comment notification API insert failed:", {
      commentId,
      status: res.status,
      body,
    })
    return
  }

  const data = (await res.json()) as { deduplicated?: boolean }
  if (data.deduplicated) {
    dispatchNotificationRefresh()
    return
  }

  dispatchNotificationRefresh()
}

/** Notify all appropriate recipients for a newly inserted comment. */
export async function ensureCommentNotificationsForInsert(
  supabase: SupabaseClient,
  params: {
    commentId: string
    senderUserId: string
    content: string
    target: CommentNotificationTarget
    ownerUserId?: string | null
    parentCommentId?: string | null
    existingComments?: Array<{ id: string; user_id: string }>
  }
): Promise<void> {
  const commentId = String(params.commentId ?? "").trim()
  if (!commentId) {
    console.error("Comment notifications skipped: missing commentId", params)
    return
  }

  const recipients = resolveCommentNotificationRecipients({
    senderUserId: params.senderUserId,
    ownerUserId: params.ownerUserId,
    parentCommentId: params.parentCommentId,
    content: params.content,
    existingComments: params.existingComments,
  })

  const parentId =
    params.parentCommentId != null ? String(params.parentCommentId) : ""
  const ownerId =
    params.ownerUserId != null ? String(params.ownerUserId).trim() : ""
  const { username: mentionedUsername } = parseLeadingCommentMention(
    params.content ?? ""
  )
  const mentionedUserId =
    mentionedUsername && params.existingComments?.length
      ? String(
          params.existingComments.find(
            (c) =>
              normalizeProfileUsername(
                (c as { profiles?: { username?: string | null } }).profiles
                  ?.username ?? ""
              ) === mentionedUsername
          )?.user_id ?? ""
        ).trim()
      : ""

  for (const recipientUserId of recipients) {
    let kind: CommentNotificationKind = "comment"
    if (parentId) {
      const parent = params.existingComments?.find(
        (c) => String(c.id) === parentId
      )
      if (parent && String(parent.user_id) === recipientUserId) {
        kind = "reply"
      }
    }
    if (
      mentionedUserId &&
      recipientUserId === mentionedUserId &&
      recipientUserId !== ownerId
    ) {
      kind = "mention"
    }

    await ensureCommentNotification(supabase, {
      recipientUserId,
      senderUserId: params.senderUserId,
      commentId,
      content: params.content,
      target: params.target,
      kind,
    })
  }
}

/** Remove notification(s) for a deleted comment (author-initiated cleanup). */
export async function deleteCommentNotificationByCommentId(
  supabase: SupabaseClient,
  commentId: string,
  senderUserId?: string
): Promise<void> {
  const id = String(commentId).trim()
  if (!id) return

  const res = await authFetch(supabase, "/api/notifications/comment", {
    method: "DELETE",
    body: JSON.stringify({ commentId: id }),
  })

  if (!res) return

  if (!res.ok) {
    const body = await res.text()
    console.error("Comment notification API delete failed:", {
      commentId: id,
      senderUserId: senderUserId ?? null,
      status: res.status,
      body,
    })
    return
  }

  dispatchNotificationRefresh()
}

/** Legacy cleanup for rows created before comment_id was stored. */
export async function deleteLegacyCommentNotification(
  supabase: SupabaseClient,
  params: {
    senderUserId: string
    content: string
    postId?: string | null
    tradeId?: string | null
    profilePostId?: string | null
    achievementPostId?: string | null
    reelId?: string | null
  }
): Promise<void> {
  const snippet = params.content.trim().slice(0, 200)
  if (!snippet) return
  if (
    !params.postId &&
    !params.tradeId &&
    !params.profilePostId &&
    !params.achievementPostId &&
    !params.reelId
  ) {
    return
  }

  const res = await authFetch(supabase, "/api/notifications/comment", {
    method: "DELETE",
    body: JSON.stringify({
      content: snippet,
      postId: params.postId ?? null,
      tradeId: params.tradeId ?? null,
      profilePostId: params.profilePostId ?? null,
      achievementPostId: params.achievementPostId ?? null,
      reelId: params.reelId ?? null,
    }),
  })

  if (!res?.ok) {
    const body = res ? await res.text() : "no session"
    console.error("Legacy comment notification API delete failed:", {
      status: res?.status,
      body,
    })
  }
}
