import type { FeedItem } from "@/app/components/feed/feedPostHelpers"
import { persistFeedSession } from "@/lib/nativeSilentCacheBridge"

type LikeMeta = { count: number; liked: boolean }

export type FeedEmptyState = "following_nobody" | "no_posts" | null

export type FeedSessionSnapshot = {
  posts: any[]
  likesByPost: Record<string, LikeMeta>
  commentCountsByPost: Record<string, number>
  commentsByPost: Record<string, any[]>
  page: number
  hasMore: boolean
  feedEmptyState: FeedEmptyState
  mergeBuffer: FeedItem[]
  tradePage: number
  profilePage: number
  achievementPage: number
  reelPage: number
  tradeExhausted: boolean
  profileExhausted: boolean
  achievementExhausted: boolean
  reelExhausted: boolean
  hasLoaded: boolean
  scrollY: number
}

const feedSessions = new Map<string, FeedSessionSnapshot>()

export function readFeedSession(key: string): FeedSessionSnapshot | null {
  return feedSessions.get(key) ?? null
}

export function writeFeedSession(key: string, snapshot: FeedSessionSnapshot) {
  feedSessions.set(key, snapshot)
  persistFeedSession(key, snapshot)
}

export function seedFeedSession(key: string, snapshot: FeedSessionSnapshot) {
  const k = key.trim()
  if (!k || feedSessions.has(k)) return
  if (!snapshot || typeof snapshot !== "object") return
  feedSessions.set(k, snapshot)
}

export function prependFeedPost(key: string, post: any) {
  const session = feedSessions.get(key)
  if (!session) return
  const postId = String(post.id)
  if (session.posts.some((p) => String(p.id) === postId)) return
  feedSessions.set(key, {
    ...session,
    posts: [post, ...session.posts],
    likesByPost: {
      ...session.likesByPost,
      [postId]: session.likesByPost[postId] ?? { count: 0, liked: false },
    },
    commentCountsByPost: {
      ...session.commentCountsByPost,
      [postId]: session.commentCountsByPost[postId] ?? 0,
    },
    commentsByPost: {
      ...session.commentsByPost,
      [postId]: session.commentsByPost[postId] ?? [],
    },
  })
}

export function clearFeedSessionsForUser(userId: string) {
  for (const key of feedSessions.keys()) {
    if (key.startsWith(`${userId}:`)) {
      feedSessions.delete(key)
    }
  }
}

/** Patch a reel row across in-memory feed sessions (caption edits, etc.). */
export function patchFeedReelInSessionsForUser(
  userId: string,
  reelId: string,
  patch: Record<string, unknown>
) {
  const id = reelId.trim()
  if (!id) return

  for (const [key, session] of feedSessions.entries()) {
    if (!key.startsWith(`${userId}:`)) continue

    let changed = false
    const nextPosts = session.posts.map((p) => {
      if (String(p.id) !== id || p.feedKind !== "reel") return p
      changed = true
      return { ...p, ...patch }
    })
    const nextBuffer = session.mergeBuffer.map((item) => {
      if (String(item.id) !== id || item.feedKind !== "reel") return item
      changed = true
      return { ...item, ...patch }
    })

    if (!changed) continue

    feedSessions.set(key, {
      ...session,
      posts: nextPosts,
      mergeBuffer: nextBuffer,
    })
  }
}

/** Remove a reel from all in-memory feed sessions after delete. */
export function removeFeedReelFromSessionsForUser(userId: string, reelId: string) {
  const id = reelId.trim()
  if (!id) return

  for (const [key, session] of feedSessions.entries()) {
    if (!key.startsWith(`${userId}:`)) continue

    const nextPosts = session.posts.filter(
      (p) => !(String(p.id) === id && p.feedKind === "reel")
    )
    const nextBuffer = session.mergeBuffer.filter(
      (item) => !(String(item.id) === id && item.feedKind === "reel")
    )

    if (
      nextPosts.length === session.posts.length &&
      nextBuffer.length === session.mergeBuffer.length
    ) {
      continue
    }

    feedSessions.set(key, {
      ...session,
      posts: nextPosts,
      mergeBuffer: nextBuffer,
    })
  }
}
