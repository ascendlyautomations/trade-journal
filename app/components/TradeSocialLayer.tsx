"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react"
import { supabase } from "../../lib/supabaseClient"
import { randomId } from "@/lib/randomId"
import FeedCommentList from "@/app/components/feed/FeedCommentList"
import EngagementCountButton from "@/app/components/EngagementCountButton"
import ActionButton from "@/app/components/ui/ActionButton"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { devLog, devWarn } from "@/lib/devLog"
import { toggleContentLike } from "@/lib/toggleContentLike"
import { ensureCommentNotificationsForInsert } from "@/lib/commentNotifications"
import {
  deleteTradeComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import ConfirmModal from "@/app/components/ui/ConfirmModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import {
  commentLikeNotificationParentFromTradeId,
} from "@/lib/commentLikes"
import { useCommentLikes } from "@/lib/useCommentLikes"
import { useHydrationReady } from "@/lib/useHydrationReady"
import {
  readTradeSocial,
  writeTradeSocial,
  appendTradeSocialComment,
  patchTradeSocialLikes,
  patchTradeSocialComments,
} from "@/lib/tradeSocialCache"
import {
  clearCommentReplyDraft,
  startCommentReply,
  type CommentReplyTarget,
} from "@/lib/commentReplyUx"
import {
  applyPinnedCommentState,
  canPinComment,
  pinTradeComment,
} from "@/lib/pinComment"

type TradeSocialContextValue = {
  tradeId: string
  currentUserId: string | undefined
  tradeOwnerUserId?: string | null | undefined
  likes: number
  liked: boolean
  comments: any[]
  showComments: boolean
  setShowComments: (open: boolean | ((prev: boolean) => boolean)) => void
  commentsExpanded: boolean
  onRequestComments?: () => void
  scrollToCommentsOnMount: boolean
  newComment: string
  setNewComment: (value: string) => void
  replyTarget: CommentReplyTarget | null
  setReplyTarget: (target: CommentReplyTarget | null) => void
  likeBusy: boolean
  commentSubmitting: boolean
  handleLike: () => Promise<void>
  handleComment: () => Promise<void>
  handleRetryComment: (comment: any) => Promise<void>
  handleDeleteComment: (comment: any) => Promise<boolean>
  handleTogglePinComment: (comment: any, pinned: boolean) => Promise<boolean>
}

const TradeSocialContext = createContext<TradeSocialContextValue | null>(null)

function useTradeSocial() {
  const ctx = useContext(TradeSocialContext)
  if (!ctx) {
    throw new Error("TradeSocial components must be inside TradeSocialProvider")
  }
  return ctx
}

type TradeSocialProviderProps = {
  tradeId: string | null | undefined
  currentUserId: string | undefined
  tradeOwnerUserId?: string | null | undefined
  /** Skip like/comment notification inserts (e.g. shared trades inside DMs). */
  suppressNotifications?: boolean
  /** Always show comments (detail modal). */
  commentsExpanded?: boolean
  /** Card list: open detail modal instead of inline comments. */
  onRequestComments?: () => void
  scrollToCommentsOnMount?: boolean
  /** Live like/comment updates via Realtime (detail views only; off for grid cards). */
  enableRealtime?: boolean
  children: ReactNode
}

export function TradeSocialProvider({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
  suppressNotifications = false,
  commentsExpanded = false,
  onRequestComments,
  scrollToCommentsOnMount = false,
  enableRealtime = false,
  children,
}: TradeSocialProviderProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [likes, setLikes] = useState(0)
  const [liked, setLiked] = useState(false)
  const [comments, setComments] = useState<any[]>([])
  const [showComments, setShowComments] = useState(false)
  const [newComment, setNewComment] = useState("")
  const [replyTarget, setReplyTarget] = useState<CommentReplyTarget | null>(null)
  const replyTargetRef = useRef<CommentReplyTarget | null>(null)
  const [likeBusy, setLikeBusy] = useState(false)
  const likeBusyRef = useRef(false)
  const [commentSubmitting, setCommentSubmitting] = useState(false)
  const commentSubmittingRef = useRef(false)

  const resolvedId = tradeId != null ? String(tradeId).trim() : ""

  useEffect(() => {
    replyTargetRef.current = replyTarget
  }, [replyTarget])

  useEffect(() => {
    if (!resolvedId) return

    let cancelled = false

    const fetchData = async () => {
      const cached = readTradeSocial(resolvedId)
      if (cached) {
        setLikes(cached.likes)
        setLiked(cached.liked)
        setComments(cached.comments)
        return
      }

      const { data: likeData } = await supabase
        .from("trade_likes")
        .select("user_id")
        .eq("trade_id", resolvedId)

      if (cancelled) return

      const rows = likeData || []
      setLikes(rows.length)
      setLiked(
        currentUserId != null &&
          rows.some((l: { user_id: string }) => l.user_id === currentUserId)
      )

      const { data: commentData } = await supabase
        .from("trade_comments")
        .select("*, profiles(username, avatar_url)")
        .eq("trade_id", resolvedId)
        .order("created_at", { ascending: true })

      if (cancelled) return

      setComments(commentData || [])
      writeTradeSocial(resolvedId, {
        likes: rows.length,
        liked:
          currentUserId != null &&
          rows.some((l: { user_id: string }) => l.user_id === currentUserId),
        comments: commentData || [],
      })
    }

    void fetchData()

    return () => {
      cancelled = true
    }
  }, [resolvedId, currentUserId])

  useEffect(() => {
    if (!resolvedId || !enableRealtime) return

    const topic = `trade-${resolvedId}-${randomId()}`
    const channel = supabase.channel(topic)

    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "trade_likes",
        filter: `trade_id=eq.${resolvedId}`,
      },
      () => {
        void (async () => {
          const { data } = await supabase
            .from("trade_likes")
            .select("user_id")
            .eq("trade_id", resolvedId)

          const rows = data || []
          const nextLiked =
            currentUserId != null &&
            rows.some((l: { user_id: string }) => l.user_id === currentUserId)
          setLikes(rows.length)
          setLiked(nextLiked)
          patchTradeSocialLikes(resolvedId, rows.length, nextLiked)
        })()
      }
    )

    channel.on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "trade_comments",
        filter: `trade_id=eq.${resolvedId}`,
      },
      (payload) => {
        void (async () => {
          const id = (payload.new as { id?: string })?.id
          if (!id) return

          const { data } = await supabase
            .from("trade_comments")
            .select("*, profiles(username, avatar_url)")
            .eq("id", id)
            .maybeSingle()

          if (!data) return
          setComments((prev) =>
            prev.some((c) => c.id === data.id) ? prev : [...prev, data]
          )
          appendTradeSocialComment(resolvedId, data)
        })()
      }
    )

    channel.on(
      "postgres_changes",
      {
        event: "UPDATE",
        schema: "public",
        table: "trade_comments",
        filter: `trade_id=eq.${resolvedId}`,
      },
      (payload) => {
        const row = payload.new as {
          id?: string
          pinned?: boolean | null
          parent_comment_id?: string | null
        }
        const id = row?.id != null ? String(row.id) : ""
        if (!id) return
        setComments((prev) =>
          applyPinnedCommentState(prev, id, row.pinned === true)
        )
      }
    )

    channel.subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [resolvedId, currentUserId, enableRealtime])

  const handleLike = useCallback(async () => {
    if (!resolvedId || !currentUserId || likeBusyRef.current || likeBusy) return

    likeBusyRef.current = true
    setLikeBusy(true)

    const prevLiked = liked
    const prevLikes = likes
    const meta = { liked: prevLiked, count: prevLikes }

    try {
      const ok = await toggleContentLike(supabase, {
        kind: "trade",
        contentId: resolvedId,
        userId: currentUserId,
        ownerUserId: suppressNotifications
          ? null
          : tradeOwnerUserId != null
            ? String(tradeOwnerUserId)
            : null,
        meta,
        onMetaChange: (next) => {
          setLiked(next.liked)
          setLikes(next.count)
          patchTradeSocialLikes(resolvedId, next.liked, next.count)
        },
      })
      if (!ok) {
        setLiked(prevLiked)
        setLikes(prevLikes)
      }
    } finally {
      likeBusyRef.current = false
      setLikeBusy(false)
    }
  }, [
    resolvedId,
    currentUserId,
    tradeOwnerUserId,
    suppressNotifications,
    liked,
    likes,
    likeBusy,
  ])

  const handleComment = useCallback(async () => {
    if (
      !resolvedId ||
      !currentUserId ||
      !newComment.trim() ||
      commentSubmittingRef.current ||
      commentSubmitting
    ) {
      return
    }

    const text = newComment.trim()
    const parentCommentId = replyTargetRef.current?.parentCommentId ?? null
    const tempId = `temp-c-${Date.now()}`
    const optimistic = {
      id: tempId,
      trade_id: resolvedId,
      user_id: currentUserId,
      content: text,
      created_at: new Date().toISOString(),
      parent_comment_id: parentCommentId,
      sync_status: "posting",
      profiles: { username: null, avatar_url: null },
    }

    commentSubmittingRef.current = true
    setCommentSubmitting(true)
    setComments((prev) => [...prev, optimistic])
    setNewComment("")
    setReplyTarget(null)

    try {
      const { data, error } = await supabase
        .from("trade_comments")
        .insert({
          trade_id: resolvedId,
          user_id: currentUserId,
          content: text,
          ...(parentCommentId ? { parent_comment_id: parentCommentId } : {}),
        })
        .select("*, profiles(username, avatar_url)")
        .single()

      if (error) {
        console.error("Trade comment error:", error)
        setComments((prev) =>
          prev.map((c) =>
            c.id === tempId ? { ...c, sync_status: "failed" } : c
          )
        )
        return
      }

      if (data) {
        const insertedRow = parentCommentId
          ? { ...data, parent_comment_id: parentCommentId }
          : data
        setComments((prev) =>
          prev.map((c) => (c.id === tempId ? insertedRow : c))
        )

        if (!suppressNotifications) {
          await ensureCommentNotificationsForInsert(supabase, {
            commentId: String(insertedRow.id),
            senderUserId: currentUserId,
            content: text,
            target: { kind: "trade", tradeId: resolvedId },
            ownerUserId: tradeOwnerUserId,
            parentCommentId,
            existingComments: comments,
          })
        }
      }
    } finally {
      commentSubmittingRef.current = false
      setCommentSubmitting(false)
    }
  }, [
    resolvedId,
    currentUserId,
    newComment,
    commentSubmitting,
    comments,
    tradeOwnerUserId,
    suppressNotifications,
  ])

  const handleRetryComment = useCallback(
    async (comment: any) => {
      if (
        !resolvedId ||
        !currentUserId ||
        commentSubmittingRef.current ||
        commentSubmitting
      ) {
        return
      }

      const tempId = String(comment.id)
      const text = String(comment.content ?? "").trim()
      if (!text || !tempId.startsWith("temp-")) return

      const parentCommentId = comment.parent_comment_id ?? null
      commentSubmittingRef.current = true
      setCommentSubmitting(true)
      setComments((prev) =>
        prev.map((c) =>
          c.id === tempId ? { ...c, sync_status: "posting" } : c
        )
      )

      try {
        const { data, error } = await supabase
          .from("trade_comments")
          .insert({
            trade_id: resolvedId,
            user_id: currentUserId,
            content: text,
            ...(parentCommentId ? { parent_comment_id: parentCommentId } : {}),
          })
          .select("*, profiles(username, avatar_url)")
          .single()

        if (error) {
          console.error("Trade comment retry error:", error)
          setComments((prev) =>
            prev.map((c) =>
              c.id === tempId ? { ...c, sync_status: "failed" } : c
            )
          )
          return
        }

        if (data) {
          const insertedRow = parentCommentId
            ? { ...data, parent_comment_id: parentCommentId }
            : data
          setComments((prev) =>
            prev.map((c) => (c.id === tempId ? insertedRow : c))
          )
        }
      } finally {
        commentSubmittingRef.current = false
        setCommentSubmitting(false)
      }
    },
    [resolvedId, currentUserId, commentSubmitting]
  )

  const handleDeleteComment = useCallback(
    async (comment: any) => {
      if (!currentUserId || !resolvedId) {
        devWarn("[comment-delete] aborted: missing user or trade", {
          currentUserId,
          tradeId: resolvedId,
        })
        return false
      }
      if (String(comment.user_id) !== String(currentUserId)) {
        devWarn("[comment-delete] aborted: not author")
        return false
      }

      const { error, deleted } = await deleteTradeComment(supabase, {
        id: String(comment.id),
        user_id: currentUserId,
        content: comment.content,
        trade_id: String(comment.trade_id ?? resolvedId),
      })

      if (error || !deleted) {
        console.error("[comment-delete] failed", {
          commentId: String(comment.id),
          userId: currentUserId,
          tradeId: resolvedId,
          error,
        })
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      setComments((prev) =>
        filterCommentsAfterDelete(prev, String(comment.id))
      )

      devLog("[comment-delete] local state updated", {
        commentId: String(comment.id),
        tradeId: resolvedId,
      })

      return true
    },
    [currentUserId, resolvedId, showPopup]
  )

  const handleTogglePinComment = useCallback(
    async (comment: any, pinned: boolean) => {
      if (!resolvedId || !currentUserId) return false
      if (
        !canPinComment({
          viewerUserId: currentUserId,
          contentOwnerUserId: tradeOwnerUserId,
        })
      ) {
        return false
      }
      if (comment.parent_comment_id) return false

      const commentId = String(comment.id)
      let previous: any[] = []
      let nextComments: any[] = []
      setComments((prev) => {
        previous = prev
        nextComments = applyPinnedCommentState(prev, commentId, pinned)
        return nextComments
      })
      patchTradeSocialComments(resolvedId, nextComments)

      const { error } = await pinTradeComment(supabase, {
        commentId,
        pinned,
        parentCommentId: comment.parent_comment_id ?? null,
      })

      if (error) {
        setComments(previous)
        patchTradeSocialComments(resolvedId, previous)
        showPopup({ type: "error", message: handleSupabaseError(error) })
        return false
      }

      return true
    },
    [currentUserId, resolvedId, showPopup, tradeOwnerUserId]
  )

  const value = useMemo<TradeSocialContextValue | null>(() => {
    if (!resolvedId) return null
    return {
      tradeId: resolvedId,
      currentUserId,
      tradeOwnerUserId,
      likes,
      liked,
      comments,
      showComments,
      setShowComments,
      commentsExpanded,
      onRequestComments,
      scrollToCommentsOnMount,
      newComment,
      setNewComment,
      replyTarget,
      setReplyTarget,
      likeBusy,
      commentSubmitting,
      handleLike,
      handleComment,
      handleRetryComment,
      handleDeleteComment,
      handleTogglePinComment,
    }
  }, [
    resolvedId,
    currentUserId,
    tradeOwnerUserId,
    likes,
    liked,
    comments,
    showComments,
    commentsExpanded,
    onRequestComments,
    scrollToCommentsOnMount,
    newComment,
    replyTarget,
    likeBusy,
    commentSubmitting,
    handleLike,
    handleComment,
    handleRetryComment,
    handleDeleteComment,
    handleTogglePinComment,
  ])

  if (!resolvedId || !value) return null

  return (
    <TradeSocialContext.Provider value={value}>
      {children}
      <FeedbackModal {...feedbackModalProps} />
    </TradeSocialContext.Provider>
  )
}

/** Likes row + 💬 toggle (comments open state lives in provider). */
export function TradeSocialEngagementBar({
  className = "",
  onCommentsFocus,
}: {
  className?: string
  onCommentsFocus?: () => void
}) {
  const {
    tradeId,
    liked,
    likes,
    comments,
    showComments,
    commentsExpanded,
    onRequestComments,
    setShowComments,
    handleLike,
    currentUserId,
    likeBusy,
  } = useTradeSocial()
  const hydrationReady = useHydrationReady()
  const likeDisabled = !hydrationReady || !currentUserId || likeBusy

  const handleCommentClick = useCallback(() => {
    onCommentsFocus?.()
    if (onRequestComments) {
      onRequestComments()
      return
    }
    if (commentsExpanded) {
      document.getElementById(`trade-comments-${tradeId}`)?.scrollIntoView({
        behavior: "smooth",
        block: "nearest",
      })
      const input = document.querySelector<HTMLInputElement>(
        `#trade-comments-${tradeId} input`
      )
      input?.focus()
      return
    }
    setShowComments(!showComments)
  }, [
    commentsExpanded,
    onCommentsFocus,
    onRequestComments,
    setShowComments,
    showComments,
    tradeId,
  ])

  return (
    <div className={`flex items-center gap-4 text-sm ${className}`}>
      <EngagementCountButton
        icon={<span>{liked ? "❤️" : "🤍"}</span>}
        count={likes}
        ariaLabel={liked ? "Unlike" : "Like"}
        disabled={likeDisabled}
        syncing={likeBusy}
        likedPop={liked}
        onClick={(e) => {
          e.stopPropagation()
          void handleLike()
        }}
        className={liked ? "text-red-400 hover:text-red-300" : undefined}
        countClassName="tabular-nums"
      />

      <EngagementCountButton
        icon={<span>💬</span>}
        count={comments.length}
        ariaLabel="View comments"
        onClick={(e) => {
          e.stopPropagation()
          handleCommentClick()
        }}
        countClassName="tabular-nums"
      />
    </div>
  )
}

/** Comment list + composer; renders nothing when `showComments` is false. */
export function TradeSocialCommentsSection({
  className = "",
  scrollContainerRef,
}: {
  className?: string
  scrollContainerRef?: RefObject<HTMLDivElement | null>
}) {
  const {
    tradeId,
    showComments,
    commentsExpanded,
    scrollToCommentsOnMount,
    comments,
    newComment,
    setNewComment,
    replyTarget,
    setReplyTarget,
    handleComment,
    handleRetryComment,
    handleDeleteComment,
    handleTogglePinComment,
    currentUserId,
    tradeOwnerUserId,
    commentSubmitting,
  } = useTradeSocial()

  const { likesByCommentId, toggleCommentLikeFor, isCommentLikeBusy, canLikeComments } =
    useCommentLikes({
      source: "trade_comments",
      comments,
      currentUserId,
      notificationParent: commentLikeNotificationParentFromTradeId(tradeId),
    })

  const sectionRef = useRef<HTMLDivElement>(null)
  const [pendingDelete, setPendingDelete] = useState<any>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)

  useEffect(() => {
    if (!scrollToCommentsOnMount || !commentsExpanded) return
    requestAnimationFrame(() => {
      const container = scrollContainerRef?.current
      const section = sectionRef.current
      if (container) {
        container.scrollTo({ top: container.scrollHeight, behavior: "smooth" })
        const input = section?.querySelector("input")
        if (input instanceof HTMLInputElement) input.focus()
        return
      }
      section?.scrollIntoView({
        behavior: "smooth",
        block: "nearest",
      })
      const input = section?.querySelector("input")
      if (input instanceof HTMLInputElement) input.focus()
    })
  }, [commentsExpanded, scrollContainerRef, scrollToCommentsOnMount, tradeId])

  const handleConfirmDelete = useCallback(async () => {
    if (!pendingDelete) return

    devLog("[comment-delete] confirm", {
      commentId: String(pendingDelete.id),
      tradeId,
      userId: pendingDelete.user_id,
    })

    setDeleteBusy(true)
    try {
      const ok = await handleDeleteComment({
        ...pendingDelete,
        trade_id: pendingDelete.trade_id ?? tradeId,
      })
      devLog("[comment-delete] handler finished", {
        commentId: String(pendingDelete.id),
        ok,
      })
      if (ok) setPendingDelete(null)
    } finally {
      setDeleteBusy(false)
    }
  }, [handleDeleteComment, pendingDelete, tradeId])

  if (!showComments && !commentsExpanded) return null

  const deleteModal = (
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
      onConfirm={handleConfirmDelete}
    />
  )

  const commentList = (
    <FeedCommentList
      comments={comments}
      currentUserId={currentUserId}
      contentOwnerUserId={tradeOwnerUserId}
      replyAvatarClassName="h-6 w-6 shrink-0 rounded-full object-cover"
      likesByCommentId={likesByCommentId}
      onToggleCommentLike={canLikeComments ? toggleCommentLikeFor : undefined}
      isCommentLikeBusy={isCommentLikeBusy}
      onReply={(comment) => {
        startCommentReply({
          comment,
          allComments: comments,
          setReplyTarget,
          setDraft: setNewComment,
          inputId: `trade-comment-input-${tradeId}`,
        })
      }}
      onRequestDelete={(comment) =>
        setPendingDelete({
          ...comment,
          trade_id: comment.trade_id ?? tradeId,
        })
      }
      onTogglePin={(comment, pinned) => {
        void handleTogglePinComment(comment, pinned)
      }}
      onRetryComment={(comment) => {
        void handleRetryComment(comment)
      }}
    />
  )

  const composer = currentUserId ? (
        <div
          className="mt-2 flex flex-col gap-2"
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
          {replyTarget ? (
            <ReplyComposerStrip
              authorName={replyTarget.authorName}
              preview={replyTarget.preview}
              onCancel={() =>
                clearCommentReplyDraft({
                  setReplyTarget,
                  setDraft: setNewComment,
                })
              }
            />
          ) : null}
          <div className="flex gap-2">
          <input
            id={`trade-comment-input-${tradeId}`}
            type="text"
            value={newComment}
            onChange={(e) => setNewComment(e.target.value)}
            onClick={(e) => e.stopPropagation()}
            onFocus={(e) => e.stopPropagation()}
            onKeyDown={(e) => {
              e.stopPropagation()
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                void handleComment()
              }
            }}
            placeholder={replyTarget ? "Add to reply…" : "Add a comment…"}
            className="flex-1 min-w-0 rounded-lg border border-gray-600 bg-[#1e293b] p-2 text-sm text-white placeholder:text-gray-400"
          />

          <ActionButton
            type="button"
            disabled={!newComment.trim()}
            syncing={commentSubmitting}
            syncingLabel="Posting…"
            onClick={(e) => {
              e.stopPropagation()
              void handleComment()
            }}
            className="shrink-0 rounded-lg bg-blue-500 px-3 text-sm font-medium text-white disabled:opacity-40"
          >
            Post
          </ActionButton>
          </div>
        </div>
      ) : null

  if (scrollContainerRef) {
    return (
      <div
        id={`trade-comments-${tradeId}`}
        ref={sectionRef}
        className={`flex min-h-0 flex-1 flex-col overflow-hidden ${className}`}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <div
          ref={scrollContainerRef}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
        >
          {commentList}
        </div>
        {composer ? <div className="shrink-0">{composer}</div> : null}
        {deleteModal}
      </div>
    )
  }

  return (
    <>
      <div
        id={`trade-comments-${tradeId}`}
        ref={sectionRef}
        className={`mt-2 space-y-3 border-t border-white/10 pt-3 ${className}`}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        {commentList}
        {composer}
      </div>
      {deleteModal}
    </>
  )
}

type TradeSocialLayerProps = {
  tradeId: string | null | undefined
  currentUserId: string | undefined
  tradeOwnerUserId?: string | null | undefined
  suppressNotifications?: boolean
  enableRealtime?: boolean
}

/** Default: engagement row immediately followed by comments panel (legacy stack). */
export default function TradeSocialLayer({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
  suppressNotifications = false,
  enableRealtime = false,
}: TradeSocialLayerProps) {
  if (!tradeId) return null

  return (
    <div onKeyDown={(e) => e.stopPropagation()}>
      <TradeSocialProvider
        tradeId={tradeId}
        currentUserId={currentUserId}
        tradeOwnerUserId={tradeOwnerUserId}
        suppressNotifications={suppressNotifications}
        enableRealtime={enableRealtime}
      >
        <TradeSocialEngagementBar className="mt-3" />
        <TradeSocialCommentsSection />
      </TradeSocialProvider>
    </div>
  )
}
