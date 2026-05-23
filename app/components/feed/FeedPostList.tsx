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
  openComments: Record<string, boolean>
  commentSubmitting: Record<string, boolean>
  draftSyncRef: MutableRefObject<Record<string, string>>
  onSelectPost: (post: any) => void
  onToggleLike: (post: any) => void
  onToggleComments: (postId: string) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostList({
  posts,
  user,
  likesByPost,
  commentsByPost,
  openComments,
  commentSubmitting,
  draftSyncRef,
  onSelectPost,
  onToggleLike,
  onToggleComments,
  onSubmitComment,
  onSharePost,
}: FeedPostListProps) {
  return (
    <>
      {posts.map((post) => {
        const pid = String(post.id)
        return (
          <FeedPostCard
            key={post.id}
            post={post}
            user={user}
            likeMeta={likesByPost[pid] ?? EMPTY_LIKE_META}
            comments={commentsByPost[pid] ?? EMPTY_COMMENTS}
            commentsOpen={!!openComments[pid]}
            commentSubmitting={!!commentSubmitting[pid]}
            draftSyncRef={draftSyncRef}
            onSelectPost={onSelectPost}
            onToggleLike={onToggleLike}
            onToggleComments={onToggleComments}
            onSubmitComment={onSubmitComment}
            onSharePost={onSharePost}
          />
        )
      })}
    </>
  )
}

export default memo(FeedPostList)
