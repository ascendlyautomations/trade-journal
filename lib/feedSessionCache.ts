import type { FeedItem } from "@/app/components/feed/feedPostHelpers"

type LikeMeta = { count: number; liked: boolean }

export type FeedEmptyState = "following_nobody" | "no_posts" | null

export type FeedSessionSnapshot = {
  posts: any[]
  likesByPost: Record<string, LikeMeta>
  commentsByPost: Record<string, any[]>
  page: number
  hasMore: boolean
  feedEmptyState: FeedEmptyState
  mergeBuffer: FeedItem[]
  tradePage: number
  profilePage: number
  achievementPage: number
  tradeExhausted: boolean
  profileExhausted: boolean
  achievementExhausted: boolean
  hasLoaded: boolean
  scrollY: number
}

const feedSessions = new Map<string, FeedSessionSnapshot>()

export function readFeedSession(key: string): FeedSessionSnapshot | null {
  return feedSessions.get(key) ?? null
}

export function writeFeedSession(key: string, snapshot: FeedSessionSnapshot) {
  feedSessions.set(key, snapshot)
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
