export const REPLY_PREVIEW_MAX = 80

export type ReplyParentProfile = {
  username?: string | null
  name?: string | null
}

export type ReplyParentMessageLike = {
  id: string
  user_id?: string | null
  sender_id?: string | null
  content?: string | null
  type?: string | null
  image_url?: string | null
  deleted_for_everyone?: boolean | null
  profiles?: ReplyParentProfile | ReplyParentProfile[] | null
}

export type ReplyParentCommentLike = {
  id: string
  user_id?: string | null
  content?: string | null
  profiles?: ReplyParentProfile | ReplyParentProfile[] | null
}

export type ReplyTarget = {
  id: string
  authorName: string
  preview: string
}

export function truncateReplyPreview(
  text: string,
  max = REPLY_PREVIEW_MAX
): string {
  const trimmed = text.trim()
  if (!trimmed) return ""
  if (trimmed.length <= max) return trimmed
  return `${trimmed.slice(0, max).trim()}…`
}

function resolveProfile(
  profiles?: ReplyParentProfile | ReplyParentProfile[] | null
): ReplyParentProfile | null {
  if (!profiles) return null
  if (Array.isArray(profiles)) return profiles[0] ?? null
  return profiles
}

export function replyAuthorLabel(
  profiles?: ReplyParentProfile | ReplyParentProfile[] | null,
  fallback = "Someone"
): string {
  const profile = resolveProfile(profiles)
  return (
    profile?.name?.trim() ||
    profile?.username?.trim() ||
    fallback
  )
}

export function previewTextFromMessage(
  message: Pick<
    ReplyParentMessageLike,
    "content" | "type" | "image_url" | "deleted_for_everyone"
  >
): string {
  if (message.deleted_for_everyone) return "Message deleted"
  const type = message.type?.trim()
  if (type === "trade") return "Shared a trade"
  if (type === "post" || type === "profile_post") return "Shared a post"
  if (message.image_url?.trim()) {
    const caption = message.content?.trim()
    if (caption) return truncateReplyPreview(caption)
    return "Sent an image"
  }
  const text = message.content?.trim()
  if (text) return truncateReplyPreview(text)
  return "New message"
}

export function previewTextFromComment(
  comment: Pick<ReplyParentCommentLike, "content">
): string {
  const text = comment.content?.trim()
  if (!text) return "Comment"
  return truncateReplyPreview(text)
}

export function buildReplyTargetFromMessage(
  message: ReplyParentMessageLike
): ReplyTarget {
  return {
    id: message.id,
    authorName: replyAuthorLabel(message.profiles),
    preview: previewTextFromMessage(message),
  }
}

export function buildReplyTargetFromComment(
  comment: ReplyParentCommentLike
): ReplyTarget {
  return {
    id: comment.id,
    authorName: replyAuthorLabel(comment.profiles),
    preview: previewTextFromComment(comment),
  }
}

export function replyParentMessageUnavailable(
  parentMessageId?: string | null,
  parent?: ReplyParentMessageLike | null
): boolean {
  if (!parentMessageId) return false
  return !parent || parent.deleted_for_everyone === true
}

export function replyParentCommentUnavailable(
  parentCommentId?: string | null,
  parent?: ReplyParentCommentLike | null
): boolean {
  if (!parentCommentId) return false
  return !parent
}

const HIGHLIGHT_CLASS = "reply-target-highlight"

function highlightElement(el: Element) {
  el.classList.add(HIGHLIGHT_CLASS)
  window.setTimeout(() => {
    el.classList.remove(HIGHLIGHT_CLASS)
  }, 2200)
}

export function scrollToReplyTarget(
  elementId: string,
  container?: HTMLElement | null
): boolean {
  if (typeof document === "undefined") return false
  let el = document.getElementById(elementId)
  if (!el && container) {
    const suffix = elementId
      .replace(/^room-message-/, "")
      .replace(/^dm-message-/, "")
    el =
      container.querySelector<HTMLElement>(
        `[data-room-message-id="${suffix}"]`
      ) ??
      container.querySelector<HTMLElement>(`[data-dm-message-id="${suffix}"]`)
  }
  if (!el) return false
  el.scrollIntoView({ behavior: "smooth", block: "center" })
  highlightElement(el)
  return true
}

export function roomMessageElementId(messageId: string): string {
  return `room-message-${messageId}`
}

export function dmMessageElementId(messageId: string): string {
  return `dm-message-${messageId}`
}

export function commentElementId(commentId: string): string {
  return `comment-${commentId}`
}

export function indexCommentsById<T extends { id: string | number }>(
  comments: T[]
): Map<string, T> {
  const byId = new Map<string, T>()
  for (const comment of comments) {
    byId.set(String(comment.id), comment)
  }
  return byId
}

export function resolveParentComment<T extends ReplyParentCommentLike>(
  comment: { parent_comment_id?: string | null },
  byId: Map<string, T>
): T | undefined {
  const parentId = comment.parent_comment_id
  if (!parentId) return undefined
  return byId.get(String(parentId))
}

export function resolveParentMessage<T extends ReplyParentMessageLike>(
  message: { parent_message_id?: string | null },
  byId: Map<string, T>
): T | undefined {
  const parentId = message.parent_message_id
  if (!parentId) return undefined
  return byId.get(String(parentId))
}
