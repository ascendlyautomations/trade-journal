"use client"

import { memo, type MutableRefObject } from "react"
import FeedPostCard, {
  EMPTY_COMMENTS,
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
  commentsByPost: Record<string, any[]>
  commentSubmitting: Record<string, boolean>
  draftSyncRef: MutableRefObject<Record<string, string>>
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onOpenLinkedTrade?: (post: any) => void
  onOpenAttachedReel?: (post: any, reel: import("@/lib/reels").ReelRow) => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
  openReelMenuId?: string | null
  onReelMenuToggle?: (reelId: string) => void
  onEditReel?: (post: any) => void
  onDeleteReel?: (post: any) => void
  onReplaceReelVideo?: (post: any) => void
}

function FeedPostList({
  posts,
  user,
  likesByPost,
  likeBusyByPost = {},
  commentsByPost,
  commentSubmitting,
  draftSyncRef,
  onSelectPost,
  onOpenComments,
  onOpenLinkedTrade,
  onOpenAttachedReel,
  onToggleLike,
  onSubmitComment,
  onSharePost,
  openReelMenuId = null,
  onReelMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
}: FeedPostListProps) {
  return (
    <>
      {posts.map((post) => {
        const pid = String(post.id)

        if (post.feedKind === "profile") {
          return (
            <FeedProfilePostCard
              key={`profile-${pid}`}
              post={post}
              user={user}
              likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
              likeBusy={!!likeBusyByPost[pid]}
              comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
              commentSubmitting={!!commentSubmitting[pid]}
              onSelectPost={onSelectPost}
              onOpenComments={onOpenComments}
              onToggleLike={onToggleLike}
              onSharePost={onSharePost}
            />
          )
        }

        if (post.feedKind === "achievement") {
          return (
            <FeedAchievementPostCard
              key={`achievement-${pid}`}
              post={post}
              user={user}
              likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
              likeBusy={!!likeBusyByPost[pid]}
              comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
              commentSubmitting={!!commentSubmitting[pid]}
              onSelectPost={onSelectPost}
              onOpenComments={onOpenComments}
              onToggleLike={onToggleLike}
              onSharePost={onSharePost}
            />
          )
        }

        if (post.feedKind === "reel") {
          const canManageReel =
            user?.id != null && String(user.id) === String(post.user_id)
          return (
            <FeedReelCard
              key={`reel-${pid}`}
              post={post}
              user={user}
              likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
              likeBusy={!!likeBusyByPost[pid]}
              comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
              commentSubmitting={!!commentSubmitting[pid]}
              canManageReel={canManageReel}
              menuOpen={openReelMenuId === pid}
              onMenuToggle={() => onReelMenuToggle?.(pid)}
              onEditReel={() => onEditReel?.(post)}
              onDeleteReel={() => onDeleteReel?.(post)}
              onReplaceReelVideo={() => onReplaceReelVideo?.(post)}
              onSelectPost={onSelectPost}
              onOpenComments={onOpenComments}
              onOpenLinkedTrade={onOpenLinkedTrade}
              onToggleLike={onToggleLike}
              onSharePost={onSharePost}
            />
          )
        }

        return (
          <FeedPostCard
            key={`trade-${pid}`}
            post={post}
            user={user}
            likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
            likeBusy={!!likeBusyByPost[pid]}
            comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
            commentSubmitting={!!commentSubmitting[pid]}
            draftSyncRef={draftSyncRef}
            onSelectPost={onSelectPost}
            onOpenComments={onOpenComments}
            onOpenAttachedReel={onOpenAttachedReel}
            onToggleLike={onToggleLike}
            onSubmitComment={onSubmitComment}
            onSharePost={onSharePost}
          />
        )
      })}
    </>
  )
}

export default memo(FeedPostList)
