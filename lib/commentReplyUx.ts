import { getCommentThreadRootId } from "@/lib/commentThreads"
import {
  indexCommentsById,
  previewTextFromComment,
  replyAuthorLabel,
  type ReplyParentCommentLike,
} from "@/lib/replyReference"
import { normalizeProfileUsername } from "@/lib/profileUsername"

export type CommentReplyTarget = {
  /** Stored as parent_comment_id — always the thread root (top-level comment). */
  parentCommentId: string
  authorName: string
  preview: string
  mentionUsername: string
  mentionUserId: string
}

export function commentAuthorUsername(
  profiles?: ReplyParentCommentLike["profiles"]
): string {
  const raw = profiles as
    | { username?: string | null; name?: string | null }
    | { username?: string | null; name?: string | null }[]
    | null
    | undefined
  const profile = Array.isArray(raw) ? raw[0] : raw
  const username = profile?.username?.trim()
  if (username) return username
  const name = profile?.name?.trim()
  if (name) return name.replace(/\s+/g, "_").toLowerCase()
  return "user"
}

export function commentReplyMentionPrefix(
  username: string | null | undefined
): string {
  const normalized = username?.trim().replace(/^@/, "")
  if (!normalized) return ""
  return `@${normalized} `
}

export function buildCommentReplyTarget(
  comment: ReplyParentCommentLike & {
    id: string | number
    parent_comment_id?: string | null
    user_id?: string | null
  },
  allComments: Array<
    ReplyParentCommentLike & {
      id: string | number
      parent_comment_id?: string | null
    }
  >
): CommentReplyTarget {
  const byId = indexCommentsById(allComments)
  const commentId = String(comment.id)
  const parentCommentId = comment.parent_comment_id
    ? getCommentThreadRootId(commentId, byId)
    : commentId

  const mentionUsername = commentAuthorUsername(comment.profiles)

  return {
    parentCommentId,
    authorName: replyAuthorLabel(comment.profiles),
    preview: previewTextFromComment(comment),
    mentionUsername,
    mentionUserId: String(comment.user_id ?? ""),
  }
}

export function parseLeadingCommentMention(content: string): {
  username: string | null
  body: string
} {
  const trimmed = content.trimStart()
  const match = trimmed.match(/^@([a-z0-9_]+)(?:\s+(.*))?$/is)
  if (!match) {
    return { username: null, body: content }
  }

  const username = normalizeProfileUsername(match[1] ?? "")
  if (!username) {
    return { username: null, body: content }
  }

  const body = (match[2] ?? "").trimStart()
  return { username, body }
}

export function buildCommentUsernameMap(
  comments: Array<{
    user_id?: string | null
    profiles?: { username?: string | null } | null
  }>
): Map<string, string> {
  const map = new Map<string, string>()
  for (const comment of comments) {
    const username = normalizeProfileUsername(comment.profiles?.username ?? "")
    const userId = comment.user_id != null ? String(comment.user_id).trim() : ""
    if (username && userId) {
      map.set(username, userId)
    }
  }
  return map
}

export function focusCommentInput(
  input: HTMLInputElement | null | undefined,
  cursorPosition?: number
): void {
  if (!input) return
  input.focus()
  const pos = cursorPosition ?? input.value.length
  try {
    input.setSelectionRange(pos, pos)
  } catch {
    /* ignore */
  }
}

export function focusCommentInputById(
  inputId: string,
  cursorPosition?: number
): void {
  if (typeof document === "undefined") return
  requestAnimationFrame(() => {
    const el = document.getElementById(inputId)
    if (el instanceof HTMLInputElement) {
      focusCommentInput(el, cursorPosition)
    }
  })
}

export function startCommentReply(params: {
  comment: ReplyParentCommentLike & {
    id: string | number
    parent_comment_id?: string | null
    user_id?: string | null
  }
  allComments: Array<
    ReplyParentCommentLike & {
      id: string | number
      parent_comment_id?: string | null
    }
  >
  setReplyTarget: (target: CommentReplyTarget) => void
  setDraft: (value: string) => void
  inputId?: string
  inputRef?: HTMLInputElement | null
  onDraftSync?: (value: string) => void
}): void {
  const target = buildCommentReplyTarget(params.comment, params.allComments)
  const prefix = commentReplyMentionPrefix(target.mentionUsername)

  params.setReplyTarget(target)
  params.setDraft(prefix)
  params.onDraftSync?.(prefix)

  if (params.inputRef) {
    requestAnimationFrame(() => {
      focusCommentInput(params.inputRef, prefix.length)
    })
    return
  }

  if (params.inputId) {
    focusCommentInputById(params.inputId, prefix.length)
  }
}

export function clearCommentReplyDraft(params: {
  setReplyTarget: (target: null) => void
  setDraft: (value: string) => void
  onDraftSync?: (value: string) => void
}): void {
  params.setReplyTarget(null)
  params.setDraft("")
  params.onDraftSync?.("")
}
