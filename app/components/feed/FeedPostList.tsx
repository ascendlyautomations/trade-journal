"use client"

import { memo, useMemo } from "react"
import FeedPostCard, {
  EMPTY_LIKE_META,
  type FeedLikeMeta,
} from "./FeedPostCard"
import FeedProfilePostCard from "./FeedProfilePostCard"
import FeedAchievementPostCard from "./FeedAchievementPostCard"
import FeedReelCard from "./FeedReelCard"

type FeedPostListProps = {
  posts: any[]
  user: any
  likesByPost: Record<string, FeedLikeMeta>
  likeBusyByPost?: Record<string, boolean>
  commentCountsByPost: Record<string, number>
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onOpenLinkedTrade?: (post: any) => void
  onOpenAttachedReel?: (post: any, reel: import("@/lib/reels").ReelRow) => void
  onToggleLike: (post: any) => void
  onSharePost: (post: any) => void
  openReelMenuId?: string | null
  onReelMenuToggle?: (reelId: string) => void
  onEditReel?: (post: any) => void
  onDeleteReel?: (post: any) => void
  onReplaceReelVideo?: (post: any) => void
  observeImpression?: (
    el: HTMLElement | null,
    post: { id: string; feedKind?: string }
  ) => void
}

function FeedPostList({
  posts,
  user,
  likesByPost,
  likeBusyByPost = {},
  commentCountsByPost,
  onSelectPost,
  onOpenComments,
  onOpenLinkedTrade,
  onOpenAttachedReel,
  onToggleLike,
  onSharePost,
  openReelMenuId = null,
  onReelMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
  observeImpression,
}: FeedPostListProps) {
  const firstMediaPostId = useMemo(
    () =>
      posts.find((post) =>
        Boolean(
          post.image_url ||
            post.thumbnail_url ||
            post.cover_url ||
            post.room_logo ||
            post.achievements?.image_url
        )
      )?.id ?? null,
    [posts]
  )

  return (
    <div className="contents">
      {posts.map((post) => {
        const pid = String(post.id)
        const impressionRef = (el: HTMLDivElement | null) => {
          observeImpression?.(el, {
            id: pid,
            feedKind: post.feedKind,
          })
        }

        if (post.feedKind === "profile") {
          return (
            <div key={`profile-wrap-${pid}`} ref={impressionRef} className="contents">
              <FeedProfilePostCard
                key={`profile-${pid}`}
                post={post}
                user={user}
                likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
                likeBusy={!!likeBusyByPost[pid]}
                commentCount={commentCountsByPost[pid] ?? 0}
                mediaPriority={String(firstMediaPostId) === pid}
                onSelectPost={onSelectPost}
                onOpenComments={onOpenComments}
                onToggleLike={onToggleLike}
                onSharePost={onSharePost}
              />
            </div>
          )
        }

        if (post.feedKind === "achievement") {
          return (
            <div key={`achievement-wrap-${pid}`} ref={impressionRef} className="contents">
            <FeedAchievementPostCard
              key={`achievement-${pid}`}
              post={post}
              user={user}
              likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
              likeBusy={!!likeBusyByPost[pid]}
              commentCount={commentCountsByPost[pid] ?? 0}
              mediaPriority={String(firstMediaPostId) === pid}
              onSelectPost={onSelectPost}
              onOpenComments={onOpenComments}
              onToggleLike={onToggleLike}
              onSharePost={onSharePost}
            />
            </div>
          )
        }

        if (post.feedKind === "reel") {
          const canManageReel =
            user?.id != null && String(user.id) === String(post.user_id)
          return (
            <div key={`reel-wrap-${pid}`} ref={impressionRef} className="contents">
            <FeedReelCard
              key={`reel-${pid}`}
              post={post}
              user={user}
              likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
              likeBusy={!!likeBusyByPost[pid]}
              commentCount={commentCountsByPost[pid] ?? 0}
              mediaPriority={String(firstMediaPostId) === pid}
              canManageReel={canManageReel}
              menuOpen={openReelMenuId === pid}
              onMenuToggle={onReelMenuToggle}
              onEditReel={onEditReel}
              onDeleteReel={onDeleteReel}
              onReplaceReelVideo={onReplaceReelVideo}
              onSelectPost={onSelectPost}
              onOpenComments={onOpenComments}
              onOpenLinkedTrade={onOpenLinkedTrade}
              onToggleLike={onToggleLike}
              onSharePost={onSharePost}
            />
            </div>
          )
        }

        return (
          <div key={`trade-wrap-${pid}`} ref={impressionRef} className="contents">
          <FeedPostCard
            key={`trade-${pid}`}
            post={post}
            user={user}
            likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
            likeBusy={!!likeBusyByPost[pid]}
            commentCount={commentCountsByPost[pid] ?? 0}
            mediaPriority={String(firstMediaPostId) === pid}
            onSelectPost={onSelectPost}
            onOpenComments={onOpenComments}
            onOpenAttachedReel={onOpenAttachedReel}
            onToggleLike={onToggleLike}
            onSharePost={onSharePost}
          />
          </div>
        )
      })}
    </div>
  )
}

export default memo(FeedPostList)
