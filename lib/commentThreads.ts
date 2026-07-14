import { indexCommentsById } from "@/lib/replyReference"

/** When a post has this many or more top-level comments, reply threads start fully collapsed. */
export const MANY_TOP_LEVEL_COMMENTS_THRESHOLD = 5

export function getCommentThreadRootId(
  commentId: string,
  byId: Map<string, { id: string | number; parent_comment_id?: string | null }>
): string {
  const visited = new Set<string>()
  let currentId = commentId

  while (true) {
    if (visited.has(currentId)) break
    visited.add(currentId)

    const comment = byId.get(currentId)
    if (!comment?.parent_comment_id) return currentId
    currentId = String(comment.parent_comment_id)
  }

  return commentId
}

export function buildCommentThreads<
  T extends {
    id: string | number
    parent_comment_id?: string | null
    created_at?: string | null
    pinned?: boolean | null
  },
>(
  comments: T[]
): { topLevel: T[]; repliesByRootId: Map<string, T[]> } {
  const byId = indexCommentsById(comments)
  const topLevel: T[] = []
  const repliesByRootId = new Map<string, T[]>()

  const sorted = [...comments].sort((a, b) => {
    const aPinned = a.pinned === true && !a.parent_comment_id ? 1 : 0
    const bPinned = b.pinned === true && !b.parent_comment_id ? 1 : 0
    if (aPinned !== bPinned) return bPinned - aPinned
    return (
      new Date(a.created_at ?? 0).getTime() -
      new Date(b.created_at ?? 0).getTime()
    )
  })

  for (const comment of sorted) {
    if (!comment.parent_comment_id) {
      topLevel.push(comment)
      continue
    }

    const rootId = getCommentThreadRootId(String(comment.id), byId)
    const list = repliesByRootId.get(rootId) ?? []
    list.push(comment)
    repliesByRootId.set(rootId, list)
  }

  // Replies stay chronological under each parent.
  for (const [rootId, list] of repliesByRootId) {
    repliesByRootId.set(
      rootId,
      [...list].sort(
        (a, b) =>
          new Date(a.created_at ?? 0).getTime() -
          new Date(b.created_at ?? 0).getTime()
      )
    )
  }

  return { topLevel, repliesByRootId }
}

export function getReplyThreadDisplay<T>(
  replies: T[],
  topLevelCommentCount: number,
  expanded: boolean
): {
  visibleReplies: T[]
  showToggle: boolean
  collapsedLabel: string | null
} {
  const count = replies.length

  if (count <= 1) {
    return {
      visibleReplies: replies,
      showToggle: false,
      collapsedLabel: null,
    }
  }

  if (expanded) {
    return {
      visibleReplies: replies,
      showToggle: true,
      collapsedLabel: null,
    }
  }

  const manyTopLevel = topLevelCommentCount >= MANY_TOP_LEVEL_COMMENTS_THRESHOLD

  if (manyTopLevel) {
    return {
      visibleReplies: [],
      showToggle: true,
      collapsedLabel: `View ${count} ${count === 1 ? "reply" : "replies"}`,
    }
  }

  const hiddenCount = count - 1
  return {
    visibleReplies: replies.slice(0, 1),
    showToggle: true,
    collapsedLabel: `View ${hiddenCount} more ${hiddenCount === 1 ? "reply" : "replies"}`,
  }
}
