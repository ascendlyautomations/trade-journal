"use client"

import { memo, useCallback, useMemo } from "react"
import { profilePostPublicUrl } from "@/lib/storagePublicUrl"
import { isRoomSharePost } from "@/lib/roomSharePost"
import FeedPostActions from "./FeedPostActions"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostScreenshot from "./FeedPostScreenshot"
import FeedRoomShareCard from "./FeedRoomShareCard"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedProfilePostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  likeBusy?: boolean
  commentCount?: number
  comments?: any[]
  mediaPriority?: boolean
  commentSubmitting?: boolean
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSharePost: (post: any) => void
}

function FeedProfilePostCard({
  post,
  user,
  likeMeta = { count: 0, liked: false },
  likeBusy = false,
  commentCount,
  comments = EMPTY_COMMENTS,
  mediaPriority = false,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSharePost,
}: FeedProfilePostCardProps) {
  const handleOpenComments = useCallback(() => {
    onOpenComments(post)
  }, [onOpenComments, post])

  const handleArticleClick = useCallback(() => {
    onSelectPost(post)
  }, [onSelectPost, post])

  const handleArticleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        onSelectPost(post)
      }
    },
    [onSelectPost, post]
  )

  const imageSrc = useMemo(
    () => profilePostPublicUrl(post.image_url),
    [post.image_url]
  )
  const avatarUrl = useMemo(() => {
    const raw = post.profiles?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles?.avatar_url])
  const profileUsername = post.profiles?.username || "User"
  const content = useMemo(() => {
    const raw = post.content != null ? String(post.content).trim() : ""
    return raw !== "" ? raw : null
  }, [post.content])
  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="cursor-pointer overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
    >
      <FeedPostHeader
        userId={post.user_id}
        avatarUrl={avatarUrl}
        username={profileUsername}
        metaLabel="Post"
        postedAt={post.created_at}
      />

      {isRoomSharePost(post) ? (
        <div className="px-4 pt-3">
          <FeedRoomShareCard
            post={post}
            viewerUserId={user?.id ?? null}
            mediaPriority={mediaPriority}
          />
        </div>
      ) : (
        <FeedPostScreenshot imageSrc={imageSrc} priority={mediaPriority} />
      )}

      <FeedPostActions
        post={post}
        user={user}
        commentCount={commentCount ?? comments.length}
        likeMeta={likeMeta}
        likeBusy={likeBusy}
        onToggleLike={onToggleLike}
        onOpenComments={handleOpenComments}
        onSharePost={onSharePost}
      />

      {content ? (
        <div className="px-4 pb-3">
          <p className="whitespace-pre-wrap text-sm leading-relaxed text-white">
            {content}
          </p>
        </div>
      ) : null}
    </article>
  )
}

export default memo(FeedProfilePostCard)

const EMPTY_COMMENTS: any[] = []
