"use client"

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type MutableRefObject,
} from "react"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import DetailModalVideo from "@/app/components/ui/DetailModalVideo"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedReelOwnerMenu from "./FeedReelOwnerMenu"
import { feedCommentTarget } from "./feedPostHelpers"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedReelDetailModalProps = {
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
  canManageReel?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onEditReel?: () => void
  onDeleteReel?: () => void
}

export default function FeedReelDetailModal({
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
  canManageReel = false,
  menuOpen = false,
  onMenuToggle,
  onEditReel,
  onDeleteReel,
}: FeedReelDetailModalProps) {
  const pid = String(post.id)
  const videoRef = useRef<HTMLVideoElement>(null)
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    () => Boolean(openCommentsRef.current[pid])
  )

  const commentTarget = useMemo(
    () => feedCommentTarget(pid, post),
    [pid, post]
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

  useEffect(() => {
    return () => {
      videoRef.current?.pause()
    }
  }, [])

  const modalDetails = useMemo(() => {
    const rawAvatar = post.profiles?.avatar_url
    const avatarUrl =
      rawAvatar != null && String(rawAvatar).trim() !== ""
        ? String(rawAvatar).trim()
        : null
    const caption =
      post.caption != null && String(post.caption).trim() !== ""
        ? String(post.caption).trim()
        : null

    return {
      avatarUrl,
      username: post.profiles?.username || "User",
      caption,
      createdAtLabel: formatSocialTimestamp(post.created_at),
    }
  }, [post])

  const splitMedia = (
    <DetailModalVideo
      ref={videoRef}
      src={String(post.video_url)}
      poster={String(post.thumbnail_url)}
    />
  )

  const splitPanel = (
    <MobileCommentFocusLayout
      commentsFocused={commentsFocused}
      header={
        <div className="flex items-center border-b border-white/5">
          <div className="min-w-0 flex-1">
            <FeedPostHeader
              userId={post.user_id}
              avatarUrl={modalDetails.avatarUrl}
              username={modalDetails.username}
            />
          </div>
          {canManageReel ? (
            <div className="pr-3">
              <FeedReelOwnerMenu
                menuOpen={menuOpen}
                onMenuToggle={() => onMenuToggle?.()}
                onEdit={() => onEditReel?.()}
                onDelete={() => onDeleteReel?.()}
              />
            </div>
          ) : null}
        </div>
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalDetails.username}
          avatarUrl={modalDetails.avatarUrl}
          timestamp={post.created_at}
          meta={<span className="text-violet-400/90">Reel</span>}
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
      engagementClassName="shrink-0 border-b border-white/10 px-4 py-2"
      collapsibleContent={
        <div className="space-y-3 border-b border-white/10 px-4 py-4 text-sm">
          {modalDetails.caption ? (
            <p className="whitespace-pre-wrap leading-relaxed text-white">
              {modalDetails.caption}
            </p>
          ) : null}
          <p className="text-xs text-white/40">{modalDetails.createdAtLabel}</p>
        </div>
      }
      comments={
        <FeedCommentsSection
          target={commentTarget}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={(context, text, parentCommentId) =>
            onSubmitComment(context, text, parentCommentId)
          }
          onDeleteComment={onDeleteComment}
        />
      }
    />
  )

  return (
    <DetailModalShell
      ariaLabel="Reel details"
      title="Reel"
      layout="split"
      onClose={onClose}
      splitMedia={splitMedia}
      splitPanel={splitPanel}
      suppressMobileSplitMedia={commentsFocused}
    />
  )
}
