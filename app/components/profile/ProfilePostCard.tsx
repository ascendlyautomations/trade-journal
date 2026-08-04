"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { scrollModalCommentsPane } from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import FeedCommentList from "@/app/components/feed/FeedCommentList"
import { useCommentLikes } from "@/lib/useCommentLikes"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import {
  clearCommentReplyDraft,
  startCommentReply,
  type CommentReplyTarget,
} from "@/lib/commentReplyUx"
import EngagementCountButton from "@/app/components/EngagementCountButton"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import FeedRoomShareCard from "@/app/components/feed/FeedRoomShareCard"
import { isRoomSharePost } from "@/lib/roomSharePost"
import FeedPostMetaRow from "@/app/components/feed/FeedPostMetaRow"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { ConfirmModal } from "@/app/components/ui"
import ExpandableText from "@/app/components/ui/ExpandableText"
import { devLog } from "@/lib/devLog"
import type { FeedLikeMeta } from "@/app/components/feed/FeedPostCard"
import type {
  ProfileCardIdentity,
  ProfilePostCardComment,
  ProfileWallPostRow,
} from "./profileTypes"

const EMPTY_COMMENTS: ProfilePostCardComment[] = []

function profileWallImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http") || raw.startsWith("blob:")) return raw
  if (raw.startsWith("/")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/profile_posts/${raw}`
}

export type ProfilePostCardProps = {
  post: ProfileWallPostRow
  profile: ProfileCardIdentity
  canManagePost?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onStartEditPost?: () => void
  onTogglePinPost?: () => void
  onSavePost?: () => void
  onDeletePost?: () => void
  showInteractions?: boolean
  onLike?: () => void
  likeBusy?: boolean
  onOpenComments?: () => void
  showCommentsPanel?: boolean
  scrollToCommentsOnMount?: boolean
  likeMeta?: FeedLikeMeta
  comments?: ProfilePostCardComment[]
  commentText?: string
  onCommentChange?: (value: string) => void
  onCommentSubmit?: (parentCommentId?: string | null) => void
  commentSubmitting?: boolean
  currentUserId?: string | null
  onDeleteComment?: (comment: ProfilePostCardComment) => Promise<boolean>
  onTogglePinComment?: (
    comment: ProfilePostCardComment,
    pinned: boolean
  ) => Promise<boolean>
  onOpenDetail?: () => void
  inDetailModal?: boolean
  disableOpen?: boolean
  onImageClick?: (url: string) => void
  onSharePost?: (post: ProfileWallPostRow) => void
}

export default function ProfilePostCard({
  post,
  profile,
  canManagePost,
  menuOpen,
  onMenuToggle,
  onStartEditPost,
  onTogglePinPost,
  onSavePost,
  onDeletePost,
  showInteractions,
  onLike,
  likeBusy = false,
  onOpenComments,
  showCommentsPanel,
  scrollToCommentsOnMount,
  likeMeta,
  comments = EMPTY_COMMENTS,
  commentText,
  onCommentChange,
  onCommentSubmit,
  commentSubmitting,
  currentUserId,
  onDeleteComment,
  onTogglePinComment,
  onOpenDetail,
  inDetailModal = false,
  disableOpen,
  onImageClick,
  onSharePost,
}: ProfilePostCardProps) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [replyTarget, setReplyTarget] = useState<CommentReplyTarget | null>(null)
  const [pendingDelete, setPendingDelete] =
    useState<ProfilePostCardComment | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [commentsFocused, setCommentsFocused] = useState(
    Boolean(scrollToCommentsOnMount && showCommentsPanel)
  )
  const imgSrc = profileWallImageSrc(post.image_url)
  const postCommentInputId = `profile-comment-input-${post.id}`

  useEffect(() => {
    // Deep-link focus is an external request that intentionally reopens comments.
    if (scrollToCommentsOnMount && showCommentsPanel) setCommentsFocused(true)
  }, [scrollToCommentsOnMount, showCommentsPanel, post.id])

  useEffect(() => {
    // A new post must not inherit reply state from the previously rendered card.
    setReplyTarget(null)
  }, [post.id])

  useEffect(() => {
    if (!showCommentsPanel || !scrollToCommentsOnMount) return
    requestAnimationFrame(() => {
      if (inDetailModal) {
        scrollModalCommentsPane(commentsScrollRef.current)
        return
      }
      const section = document.getElementById(`profile-post-comments-${post.id}`)
      section?.scrollIntoView({ behavior: "smooth", block: "nearest" })
      const input = section?.querySelector("input")
      if (input instanceof HTMLInputElement) input.focus()
    })
  }, [inDetailModal, post.id, scrollToCommentsOnMount, showCommentsPanel])

  const commentLikeNotificationParent = useMemo(
    () => ({ profilePostId: String(post.id) }),
    [post.id]
  )
  const { likesByCommentId, toggleCommentLikeFor, isCommentLikeBusy, canLikeComments } =
    useCommentLikes({
      source: "profile_post_comments",
      comments,
      currentUserId,
      notificationParent: commentLikeNotificationParent,
    })

  const commentsList = (
    <FeedCommentList
      comments={comments}
      currentUserId={currentUserId}
      contentOwnerUserId={profile?.id}
      likesByCommentId={likesByCommentId}
      onToggleCommentLike={canLikeComments ? toggleCommentLikeFor : undefined}
      isCommentLikeBusy={isCommentLikeBusy}
      onReply={(comment) => {
        startCommentReply({
          comment,
          allComments: comments,
          setReplyTarget,
          setDraft: (value) => onCommentChange?.(value),
          inputId: postCommentInputId,
        })
      }}
      onRequestDelete={
        onDeleteComment
          ? (comment) =>
              setPendingDelete({
                ...comment,
                profile_post_id: comment.profile_post_id ?? post.id,
              })
          : undefined
      }
      onTogglePin={
        onTogglePinComment
          ? (comment, pinned) => {
              void onTogglePinComment(comment, pinned)
            }
          : undefined
      }
      deleteMenuClassName="z-[9100]"
    />
  )

  const commentsComposer = (
    <div className="flex flex-col gap-2">
      {replyTarget ? (
        <ReplyComposerStrip
          authorName={replyTarget.authorName}
          preview={replyTarget.preview}
          onCancel={() =>
            clearCommentReplyDraft({
              setReplyTarget,
              setDraft: (value) => onCommentChange?.(value),
            })
          }
        />
      ) : null}
      <div className="flex gap-2">
      <input
        id={postCommentInputId}
        value={commentText || ""}
        onChange={(e) => onCommentChange?.(e.target.value)}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault()
            if (!commentSubmitting) {
              onCommentSubmit?.(replyTarget?.parentCommentId ?? null)
              setReplyTarget(null)
            }
          }
        }}
        placeholder={replyTarget ? "Add to reply…" : "Add a comment..."}
        className="flex-1 rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white placeholder:text-gray-400"
      />
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          onCommentSubmit?.(replyTarget?.parentCommentId ?? null)
          setReplyTarget(null)
        }}
        disabled={commentSubmitting || !(commentText || "").trim()}
        className="rounded-lg bg-blue-500 px-3 py-2 text-sm text-white disabled:opacity-40"
      >
        Post
      </button>
      </div>
    </div>
  )

  const commentsPanel = showCommentsPanel ? (
    <div
      id={`profile-post-comments-${post.id}`}
      className="mt-3 space-y-3"
    >
      <div className="max-h-48 space-y-1 overflow-y-auto text-sm text-gray-300">
        {commentsList}
      </div>
      {commentsComposer}
    </div>
  ) : null

  const cardShellClass = inDetailModal
    ? "flex min-h-0 flex-1 flex-col overflow-hidden bg-transparent md:flex-row"
    : `h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`

  const postAuthorHeader = (
    <div className="flex shrink-0 items-center justify-between gap-3 border-b border-white/5 px-3 py-2 md:p-4">
      <div className="flex min-w-0 items-center gap-2.5 md:gap-3">
        <ProfileAvatarImg
          src={profile.avatar_url}
          className="h-9 w-9 ring-2 ring-white/10 md:h-10 md:w-10"
        />
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-white">
            {profile.username || "User"}
          </p>
          <FeedPostMetaRow
            label="Post"
            createdAt={post.created_at}
            suffix={
              post.is_pinned ? (
                <span className="ml-2 text-yellow-400" aria-label="Pinned">
                  📌
                </span>
              ) : null
            }
          />
        </div>
      </div>
      {canManagePost ? (
        <div className="relative">
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onMenuToggle?.()
            }}
            className="px-1 text-gray-400 hover:text-white"
          >
            •••
          </button>
          {menuOpen ? (
            <div
              className="absolute right-0 z-50 mt-2 w-40 rounded-lg border border-white/10 bg-[#020617] shadow-lg"
              onClick={(e) => e.stopPropagation()}
            >
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onStartEditPost?.()
                }}
                className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
              >
                Edit Post
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onTogglePinPost?.()
                }}
                className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
              >
                {post.is_pinned ? "Unpin Post" : "Pin Post"}
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onSavePost?.()
                }}
                className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
              >
                Save Post
              </button>
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onDeletePost?.()
                }}
                className="block w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-white/10"
              >
                Delete Post
              </button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )

  const postImageBlock =
    imgSrc != null ? (
      <DetailModalImage src={imgSrc} onClick={onImageClick} />
    ) : null

  const postEngagementRow = showInteractions ? (
    <div className="flex items-center gap-4 px-1 text-sm">
      <EngagementCountButton
        icon={<span>{likeMeta?.liked ? "❤️" : "🤍"}</span>}
        count={likeMeta?.count ?? 0}
        ariaLabel={likeMeta?.liked ? "Unlike" : "Like"}
        disabled={likeBusy}
        syncing={likeBusy}
        likedPop={!!likeMeta?.liked}
        onClick={(e) => {
          e.stopPropagation()
          onLike?.()
        }}
        className="text-gray-300 hover:text-white"
        countClassName="tabular-nums"
      />
      <EngagementCountButton
        icon={<span>💬</span>}
        count={comments?.length ?? 0}
        ariaLabel="View comments"
        onClick={(e) => {
          e.stopPropagation()
          setCommentsFocused(true)
          onOpenComments?.()
          if (inDetailModal && showCommentsPanel) {
            requestAnimationFrame(() => {
              scrollModalCommentsPane(commentsScrollRef.current)
            })
          }
        }}
        className="text-gray-300 hover:text-white"
        countClassName="tabular-nums"
      />
      {onSharePost ? (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            onSharePost(post)
          }}
          className="flex h-9 w-9 items-center justify-center rounded-lg bg-white/5 text-gray-300 transition hover:bg-white/10 hover:text-white"
          aria-label="Share post"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
            />
          </svg>
        </button>
      ) : null}
    </div>
  ) : null

  const postContentBlock = (
    <div className="shrink-0 space-y-2 px-3 py-2.5 md:space-y-3 md:p-4">
      {post.content ? (
        <ExpandableText
          className="min-w-0 text-sm leading-snug text-white md:leading-relaxed"
          textClassName="break-words text-white"
          collapsedLines={3}
          stopPropagation
        >
          {post.content}
        </ExpandableText>
      ) : null}
      {showInteractions ? (
        <div className="border-t border-white/10 pt-2 md:pt-3">
          {postEngagementRow}
          {!inDetailModal ? commentsPanel : null}
        </div>
      ) : null}
    </div>
  )

  const postCollapsibleContent = (
    <div className="shrink-0 space-y-2 px-3 py-2.5 md:space-y-3 md:p-4">
      {post.content ? (
        <ExpandableText
          className="min-w-0 text-sm leading-snug text-white md:leading-relaxed"
          textClassName="break-words text-white"
          collapsedLines={3}
          stopPropagation
        >
          {post.content}
        </ExpandableText>
      ) : null}
    </div>
  )

  const deleteModal = onDeleteComment ? (
    <ConfirmModal
      open={pendingDelete != null}
      title="Delete Comment?"
      description="This action cannot be undone."
      confirmLabel="Delete"
      destructive
      loading={deleteBusy}
      onCancel={() => {
        if (!deleteBusy) setPendingDelete(null)
      }}
      onConfirm={async () => {
        if (!pendingDelete || !onDeleteComment) return
        devLog("[comment-delete] confirm", {
          commentId: String(pendingDelete.id),
          postId: pendingDelete.post_id ?? post.id,
        })
        setDeleteBusy(true)
        try {
          const ok = await onDeleteComment({
            ...pendingDelete,
            post_id: pendingDelete.post_id ?? post.id,
          })
          devLog("[comment-delete] handler finished", {
            commentId: String(pendingDelete.id),
            ok,
          })
          if (ok) setPendingDelete(null)
        } finally {
          setDeleteBusy(false)
        }
      }}
    />
  ) : null

  if (inDetailModal) {
    const postCommentsPanel = showCommentsPanel ? (
      <div
        id={`profile-post-comments-${post.id}`}
        className="flex min-h-0 flex-1 flex-col overflow-hidden"
      >
        <div
          ref={commentsScrollRef}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pt-3"
        >
          {commentsList}
        </div>
        <div className="shrink-0 px-4 pb-4 pt-3">{commentsComposer}</div>
      </div>
    ) : null

    return (
      <>
        <article className={cardShellClass}>
          {isRoomSharePost(post) ? (
            <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:p-3">
              <FeedRoomShareCard
                post={post}
                viewerUserId={currentUserId ?? null}
                className="w-full max-w-md"
              />
            </div>
          ) : imgSrc ? (
            <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:p-3">
              {postImageBlock}
            </div>
          ) : null}

          <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:w-[400px] md:shrink-0 lg:w-[420px]">
            <MobileCommentFocusLayout
              commentsFocused={commentsFocused}
              header={postAuthorHeader}
              compactHeader={
                <CommentFocusCompactStrip
                  userId={String(profile.id ?? "")}
                  username={profile.username}
                  avatarUrl={profile.avatar_url}
                  meta={
                    <FeedPostMetaRow label="Post" createdAt={post.created_at} />
                  }
                  onExpand={() => setCommentsFocused(false)}
                />
              }
              mobileMedia={
                isRoomSharePost(post) ? (
                  <FeedRoomShareCard
                    post={post}
                    viewerUserId={currentUserId ?? null}
                    className="mx-4 my-3"
                  />
                ) : (
                  postImageBlock ?? undefined
                )
              }
              engagement={postEngagementRow}
              engagementClassName="shrink-0 border-b border-white/10 px-3 py-1.5 md:px-4 md:py-2"
              collapsibleContent={postCollapsibleContent}
              comments={postCommentsPanel}
            />
          </div>
        </article>
        {deleteModal}
      </>
    )
  }

  return (
    <>
      <article
      className={cardShellClass}
      role={onOpenDetail && !disableOpen ? "button" : undefined}
      tabIndex={onOpenDetail && !disableOpen ? 0 : undefined}
      onClick={() => {
        if (onOpenDetail && !disableOpen) onOpenDetail()
      }}
      onKeyDown={(e) => {
        if (!onOpenDetail || disableOpen) return
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onOpenDetail()
        }
      }}
    >
      {postAuthorHeader}

      {isRoomSharePost(post) ? (
        <div className="p-3 md:p-4" onClick={(e) => e.stopPropagation()}>
          <FeedRoomShareCard
            post={post}
            viewerUserId={currentUserId ?? null}
          />
        </div>
      ) : imgSrc ? (
        <>
          <div className="relative h-[min(46dvh,280px)] w-full overflow-hidden md:hidden">
            <TradeScreenshotImage
              src={imgSrc}
              preset="feed-thumb"
              objectFit="cover"
              className="h-full w-full rounded-none"
              logContext="profile-post-card-mobile"
              onClick={onImageClick}
            />
          </div>
          <div className="hidden w-full md:block">
            <TradeScreenshotImage
              src={imgSrc}
              preset="feed-thumb"
              className="rounded-none"
              logContext="profile-post-card"
              onClick={onImageClick}
            />
          </div>
        </>
      ) : null}

      {postContentBlock}
    </article>
      {deleteModal}
    </>
  )
}