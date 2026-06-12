"use client"

import { memo, type MutableRefObject } from "react"
import FeedPostCard, {
  EMPTY_COMMENTS,
  EMPTY_LIKE_META,
  type FeedLikeMeta,
} from "./FeedPostCard"

type FeedPostListProps = {
  posts: any[]
  user: any
  likesByPost: Record<string, FeedLikeMeta>
  commentsByPost: Record<string, any[]>
  commentSubmitting: Record<string, boolean>
  draftSyncRef: MutableRefObject<Record<string, string>>
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostList({
  posts,
  user,
  likesByPost,
  commentsByPost,
  commentSubmitting,
  draftSyncRef,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSubmitComment,
  onSharePost,
}: FeedPostListProps) {
  return (
    <>
      {posts.map((post) => {
        const pid = String(post.id)
        return (
          <FeedPostCard
            key={pid}
            post={post}
            user={user}
            likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
            comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
            commentSubmitting={!!commentSubmitting[pid]}
            draftSyncRef={draftSyncRef}
            onSelectPost={onSelectPost}
            onOpenComments={onOpenComments}
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
