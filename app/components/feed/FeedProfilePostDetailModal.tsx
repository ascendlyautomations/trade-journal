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
import { formatEST } from "@/lib/formatEST"
import { profilePostPublicUrl } from "@/lib/storagePublicUrl"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedProfilePostDetailModalProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onSharePost: (post: any) => void
}

export default function FeedProfilePostDetailModal({
  post,
  user,
  comments,
  likeMeta,
  likeBusy = false,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onClose,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
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
      createdAtLabel: formatEST(post.created_at),
      avatarUrl,
      username: post.profiles?.username || "User",
    }
  }, [post])

  const splitMedia =
    modalPostDetails.imageSrc != null ? (
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
        />
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalPostDetails.username}
          avatarUrl={modalPostDetails.avatarUrl}
          timestamp={post.created_at}
          meta={<span className="text-sky-400/90">Post</span>}
          onExpand={() => setCommentsFocused(false)}
        />
      }
      engagement={
        <PostInteractionsEngagement
          post={post}
          user={user}
          comments={comments}
          likeMeta={likeMeta}
          likeBusy={likeBusy}
          onToggleLike={onToggleLike}
          onOpenComments={() => focusComments()}
          onSharePost={onSharePost}
        />
      }
      collapsibleContent={
        <div className="space-y-3 border-b border-white/10 px-4 py-4 text-sm">
          {modalPostDetails.content ? (
            <p className="whitespace-pre-wrap leading-relaxed text-white">
              {modalPostDetails.content}
            </p>
          ) : null}
          <p className="text-xs text-white/40">{modalPostDetails.createdAtLabel}</p>
        </div>
      }
      comments={
        <FeedCommentsSection
          post={post}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={onSubmitComment}
          onDeleteComment={onDeleteComment}
        />
      }
    />
  )

  return (
    <>
      <DetailModalShell
        ariaLabel="Post details"
        title="Post"
        layout="split"
        onClose={onClose}
        splitMedia={splitMedia}
        splitPanel={splitPanel}
        suppressMobileSplitMedia={commentsFocused}
      />
      <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
    </>
  )
}
