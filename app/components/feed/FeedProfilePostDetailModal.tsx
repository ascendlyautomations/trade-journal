"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import {
  achievementFromPost,
  isAchievementFeedPost,
} from "@/lib/achievementPostEngagement"
import { isRoomSharePost } from "@/lib/roomSharePost"
import {
  achievementImagePublicUrl,
  profilePostPublicUrl,
} from "@/lib/storagePublicUrl"
import FeedAchievementDetailMeta from "./FeedAchievementDetailMeta"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostMetaRow from "./FeedPostMetaRow"
import FeedRoomShareCard from "./FeedRoomShareCard"
import { feedCommentTarget } from "./feedPostHelpers"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedProfilePostDetailModalProps = {
  post: any
  user: any
  comments: any[]
  commentCount: number
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (
    post: any,
    text: string,
    parentCommentId?: string | null,
    retryTempId?: string | null
  ) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onTogglePinComment?: (comment: any, pinned: boolean) => Promise<boolean>
  onSharePost: (post: any) => void
}

export default function FeedProfilePostDetailModal({
  post,
  user,
  comments,
  commentCount,
  likeMeta,
  likeBusy = false,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onClose,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
  onTogglePinComment,
  onSharePost,
}: FeedProfilePostDetailModalProps) {
  const pid = String(post.id)
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    () => Boolean(openCommentsRef.current[pid])
  )

  const scrollCommentsIntoView = useCallback(() => {
    requestAnimationFrame(() => {
      scrollModalCommentsPane(commentsScrollRef.current)
    })
  }, [])

  const focusComments = useCallback(() => {
    setCommentsFocused(true)
    scrollCommentsIntoView()
  }, [scrollCommentsIntoView])

  useEffect(() => {
    if (openCommentsRef.current[pid]) {
      setCommentsFocused(true)
      scrollCommentsIntoView()
      openCommentsRef.current[pid] = false
    }
  }, [openCommentsRef, pid, scrollCommentsIntoView])

  const isAchievement = isAchievementFeedPost(post)
  const achievement = useMemo(
    () => (isAchievement ? achievementFromPost(post) : null),
    [isAchievement, post]
  )
  const achievementImageSrc = useMemo(
    () =>
      achievement ? achievementImagePublicUrl(achievement.image_url) : null,
    [achievement]
  )

  useEffect(() => {
    if (!achievementImageSrc) return
    const img = new Image()
    img.src = achievementImageSrc
  }, [achievementImageSrc])

  const modalPostDetails = useMemo(() => {
    const rawAvatar = post.profiles?.avatar_url
    const avatarUrl =
      rawAvatar != null && String(rawAvatar).trim() !== ""
        ? String(rawAvatar).trim()
        : null
    const content =
      post.content != null && String(post.content).trim() !== ""
        ? String(post.content).trim()
        : null

    return {
      imageSrc: profilePostPublicUrl(post.image_url),
      content,
      avatarUrl,
      username: post.profiles?.username || "User",
    }
  }, [post])

  const splitMedia = isAchievement && achievement ? (
    achievementImageSrc ? (
      <DetailModalImage
        src={achievementImageSrc}
        onClick={setLightboxUrl}
      />
    ) : (
      <div className="flex h-full w-full items-center justify-center p-6 text-sm text-gray-400">
        No certificate image
      </div>
    )
  ) : isRoomSharePost(post) ? (
    <div className="flex h-full w-full items-center justify-center p-4">
      <FeedRoomShareCard
        post={post}
        viewerUserId={user?.id ?? null}
        className="w-full max-w-md"
      />
    </div>
  ) : modalPostDetails.imageSrc != null ? (
    <DetailModalImage
      src={modalPostDetails.imageSrc}
      onClick={setLightboxUrl}
    />
  ) : null

  const splitPanel = (
    <MobileCommentFocusLayout
      commentsFocused={commentsFocused}
      header={
        <FeedPostHeader
          userId={post.user_id}
          avatarUrl={modalPostDetails.avatarUrl}
          username={modalPostDetails.username}
          metaLabel={isAchievement ? "Achievement" : "Post"}
          metaLabelClassName={
            isAchievement
              ? "font-medium text-amber-400/90"
              : "font-medium text-sky-400/90"
          }
          postedAt={post.created_at}
        />
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalPostDetails.username}
          avatarUrl={modalPostDetails.avatarUrl}
          meta={
            <FeedPostMetaRow
              label={isAchievement ? "Achievement" : "Post"}
              labelClassName={
                isAchievement ? "font-medium text-amber-400/90" : undefined
              }
              createdAt={post.created_at}
            />
          }
          onExpand={() => setCommentsFocused(false)}
        />
      }
      engagement={
        <PostInteractionsEngagement
          post={post}
          user={user}
          comments={comments}
          commentCount={commentCount}
          likeMeta={likeMeta}
          likeBusy={likeBusy}
          onToggleLike={onToggleLike}
          onOpenComments={() => focusComments()}
          onSharePost={onSharePost}
        />
      }
      collapsibleContent={
        isAchievement && achievement ? (
          <FeedAchievementDetailMeta achievement={achievement} />
        ) : (
        <div className="space-y-3 border-b border-white/10 px-4 py-4 text-sm">
          {modalPostDetails.content ? (
            <p className="whitespace-pre-wrap leading-relaxed text-white">
              {modalPostDetails.content}
            </p>
          ) : null}
        </div>
        )
      }
      comments={
        <FeedCommentsSection
          target={feedCommentTarget(pid, post)}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={(context, text, parentCommentId, retryTempId) =>
            onSubmitComment(context, text, parentCommentId, retryTempId)
          }
          onDeleteComment={onDeleteComment}
          onTogglePinComment={onTogglePinComment}
        />
      }
    />
  )

  return (
    <>
      <DetailModalShell
        ariaLabel={isAchievement ? "Achievement details" : "Post details"}
        title={isAchievement ? "Achievement" : "Post"}
        layout="split"
        onClose={onClose}
        splitMedia={splitMedia}
        splitPanel={splitPanel}
        suppressMobileSplitMedia={commentsFocused}
      />
      <ImageLightbox
        imageUrl={lightboxUrl}
        onClose={() => setLightboxUrl(null)}
        alt={achievement?.title ?? "Achievement certificate"}
      />
    </>
  )
}
