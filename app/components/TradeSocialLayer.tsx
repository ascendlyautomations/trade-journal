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
import FeedCommentItem from "@/app/components/feed/FeedCommentItem"
import EngagementCountButton from "@/app/components/EngagementCountButton"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import {
  deleteLikeNotification,
  ensureLikeNotification,
} from "@/lib/likeNotifications"
import {
  deleteTradeComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import ConfirmModal from "@/app/components/ui/ConfirmModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import {
  buildReplyTargetFromComment,
  indexCommentsById,
  resolveParentComment,
  type ReplyTarget,
} from "@/lib/replyReference"

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
  replyTarget: ReplyTarget | null
  setReplyTarget: (target: ReplyTarget | null) => void
  likeBusy: boolean
  commentSubmitting: boolean
  handleLike: () => Promise<void>
  handleComment: () => Promise<void>
  handleDeleteComment: (comment: any) => Promise<boolean>
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
  const [replyTarget, setReplyTarget] = useState<ReplyTarget | null>(null)
  const replyTargetRef = useRef<ReplyTarget | null>(null)
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
    }

    void fetchData()

    return () => {
      cancelled = true
    }
  }, [resolvedId, currentUserId])

  useEffect(() => {
    if (!resolvedId || !enableRealtime) return

    const topic = `trade-${resolvedId}-${crypto.randomUUID()}`
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
          setLikes(rows.length)
          setLiked(
            currentUserId != null &&
              rows.some((l: { user_id: string }) => l.user_id === currentUserId)
          )
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
        })()
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

    try {
    const { data: existing } = await supabase
      .from("trade_likes")
      .select("id")
      .eq("trade_id", resolvedId)
      .eq("user_id", currentUserId)
      .maybeSingle()

    if (existing) {
      const { error } = await supabase
        .from("trade_likes")
        .delete()
        .eq("trade_id", resolvedId)
        .eq("user_id", currentUserId)

      if (error) {
        console.error("Unlike trade error:", error)
        return
      }

      if (!suppressNotifications) {
        const receiverId =
          tradeOwnerUserId != null ? String(tradeOwnerUserId).trim() : ""
        if (receiverId && receiverId !== currentUserId) {
          await deleteLikeNotification(supabase, {
            recipientUserId: receiverId,
            senderUserId: currentUserId,
            target: { kind: "trade", tradeId: resolvedId },
          })
        }
      }

      setLiked(false)
      setLikes((prev) => Math.max(0, prev - 1))
    } else {
      const { error } = await supabase.from("trade_likes").insert({
        trade_id: resolvedId,
        user_id: currentUserId,
      })

      if (error) {
        console.error("Like trade error:", error)
        return
      }

      setLiked(true)
      setLikes((prev) => prev + 1)

      if (!suppressNotifications) {
        const receiverId =
          tradeOwnerUserId != null ? String(tradeOwnerUserId).trim() : ""
        if (receiverId && receiverId !== currentUserId) {
          await ensureLikeNotification(supabase, {
            recipientUserId: receiverId,
            senderUserId: currentUserId,
            target: { kind: "trade", tradeId: resolvedId },
          })
        }
      }
    }
    } finally {
      likeBusyRef.current = false
      setLikeBusy(false)
    }
  }, [resolvedId, currentUserId, tradeOwnerUserId, suppressNotifications])

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

    commentSubmittingRef.current = true
    setCommentSubmitting(true)

    try {
    const { data, error } = await supabase
      .from("trade_comments")
      .insert({
        trade_id: resolvedId,
        user_id: currentUserId,
        content: newComment.trim(),
        ...(replyTargetRef.current?.id
          ? { parent_comment_id: replyTargetRef.current.id }
          : {}),
      })
      .select("*, profiles(username, avatar_url)")
      .single()

    if (error) {
      console.error("Trade comment error:", error)
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    if (data) {
      const insertedRow = replyTargetRef.current?.id
        ? { ...data, parent_comment_id: replyTargetRef.current.id }
        : data
      setComments((prev) => [...prev, insertedRow])
      setNewComment("")
      setReplyTarget(null)

      if (!suppressNotifications) {
        const receiverId =
          tradeOwnerUserId != null ? String(tradeOwnerUserId).trim() : ""
        if (receiverId && receiverId !== currentUserId) {
          const { error: nErr } = await supabase.from("notifications").insert({
            user_id: receiverId,
            sender_id: currentUserId,
            type: "comment",
            trade_id: resolvedId,
            content: newComment.trim().slice(0, 200),
          })

          if (nErr) {
            console.error("Notification error:", nErr?.message, nErr)
            return
          }

          window.dispatchEvent(new CustomEvent("notification-update"))
          window.dispatchEvent(
            new CustomEvent("tj-unread-notifications-refresh")
          )
        }
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
    tradeOwnerUserId,
    suppressNotifications,
    showPopup,
  ])

  const handleDeleteComment = useCallback(
    async (comment: any) => {
      if (!currentUserId || !resolvedId) {
        console.warn("[comment-delete] aborted: missing user or trade", {
          currentUserId,
          tradeId: resolvedId,
        })
        return false
      }
      if (String(comment.user_id) !== String(currentUserId)) {
        console.warn("[comment-delete] aborted: not author")
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

      console.log("[comment-delete] local state updated", {
        commentId: String(comment.id),
        tradeId: resolvedId,
      })

      return true
    },
    [currentUserId, resolvedId, showPopup]
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
      handleDeleteComment,
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
    handleDeleteComment,
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
        disabled={!currentUserId || likeBusy}
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
    handleDeleteComment,
    currentUserId,
    commentSubmitting,
  } = useTradeSocial()

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

  const commentsById = useMemo(() => indexCommentsById(comments), [comments])

  const handleConfirmDelete = useCallback(async () => {
    if (!pendingDelete) return

    console.log("[comment-delete] confirm", {
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
      console.log("[comment-delete] handler finished", {
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
    <div className="space-y-2">
      {comments.map((c) => (
        <FeedCommentItem
          key={c.id}
          comment={c}
          parentComment={resolveParentComment(c, commentsById)}
          currentUserId={currentUserId}
          avatarClassName="h-6 w-6 shrink-0 rounded-full object-cover"
          onReply={(comment) => {
            setReplyTarget(buildReplyTargetFromComment(comment))
            const input = sectionRef.current?.querySelector("input")
            if (input instanceof HTMLInputElement) input.focus()
          }}
          onRequestDelete={(comment) =>
            setPendingDelete({
              ...comment,
              trade_id: comment.trade_id ?? tradeId,
            })
          }
        />
      ))}
    </div>
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
              onCancel={() => setReplyTarget(null)}
            />
          ) : null}
          <div className="flex gap-2">
          <input
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
            placeholder={replyTarget ? "Write a reply…" : "Add a comment…"}
            className="flex-1 min-w-0 rounded-lg border border-gray-600 bg-[#1e293b] p-2 text-sm text-white placeholder:text-gray-500"
          />

          <button
            type="button"
            disabled={!newComment.trim() || commentSubmitting}
            onClick={(e) => {
              e.stopPropagation()
              void handleComment()
            }}
            className="shrink-0 rounded-lg bg-blue-500 px-3 text-sm font-medium text-white disabled:opacity-40"
          >
            Post
          </button>
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
