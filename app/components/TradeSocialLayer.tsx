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
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import {
  ProfileAvatarLink,
  ProfileLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"

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
  likeBusy: boolean
  commentSubmitting: boolean
  handleLike: () => Promise<void>
  handleComment: () => Promise<void>
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
  children,
}: TradeSocialProviderProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [likes, setLikes] = useState(0)
  const [liked, setLiked] = useState(false)
  const [comments, setComments] = useState<any[]>([])
  const [showComments, setShowComments] = useState(false)
  const [newComment, setNewComment] = useState("")
  const [likeBusy, setLikeBusy] = useState(false)
  const likeBusyRef = useRef(false)
  const [commentSubmitting, setCommentSubmitting] = useState(false)
  const commentSubmittingRef = useRef(false)

  const resolvedId = tradeId != null ? String(tradeId).trim() : ""

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
        .select(
          `
          *,
          profiles (username, avatar_url)
        `
        )
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
    if (!resolvedId) return

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
            .select(
              `
              *,
              profiles (username, avatar_url)
            `
            )
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
  }, [resolvedId, currentUserId])

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
          const { error: nErr } = await supabase.from("notifications").insert({
            user_id: receiverId,
            sender_id: currentUserId,
            type: "like",
            trade_id: resolvedId,
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
    const userIsPro = await isUserPro(supabase as any, currentUserId)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        currentUserId,
        10
      )
      if (limitReached) {
        showPopup(feedbackPresets.messageLimit())
        return
      }
    }

    const { data, error } = await supabase
      .from("trade_comments")
      .insert({
        trade_id: resolvedId,
        user_id: currentUserId,
        content: newComment.trim(),
      })
      .select(
        `
        *,
        profiles (username, avatar_url)
      `
      )
      .single()

    if (error) {
      console.error("Trade comment error:", error)
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    if (data) {
      setComments((prev) => [...prev, data])
      setNewComment("")

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
      likeBusy,
      commentSubmitting,
      handleLike,
      handleComment,
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
    likeBusy,
    commentSubmitting,
    handleLike,
    handleComment,
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
}: {
  className?: string
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
    onRequestComments,
    setShowComments,
    showComments,
    tradeId,
  ])

  return (
    <div className={`flex items-center gap-4 text-sm ${className}`}>
      <button
        type="button"
        disabled={!currentUserId || likeBusy}
        onClick={(e) => {
          e.stopPropagation()
          void handleLike()
        }}
        className={`flex items-center gap-1 disabled:opacity-50 ${
          liked ? "text-red-400" : "text-gray-400"
        }`}
      >
        <span aria-hidden>{liked ? "❤️" : "🤍"}</span>
        <span className="tabular-nums">{likes}</span>
      </button>

      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          handleCommentClick()
        }}
        className="text-gray-400 hover:text-gray-200"
        aria-label="View comments"
      >
        💬 {comments.length}
      </button>
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
    handleComment,
    currentUserId,
    commentSubmitting,
  } = useTradeSocial()

  const sectionRef = useRef<HTMLDivElement>(null)

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

  if (!showComments && !commentsExpanded) return null

  const commentList = (
    <div className="space-y-2">
        {comments.map((c) => {
          const userId = String(c.user_id ?? "")
          const username = c.profiles?.username
          const av = c.profiles?.avatar_url
          const hasAv =
            av != null && String(av).trim() !== "" && String(av) !== "null"
          return (
            <div key={c.id} className="flex items-start gap-2">
              {hasAv ? (
                <ProfileAvatarLink
                  userId={userId}
                  username={username}
                  src={String(av).trim()}
                  imgClassName="h-6 w-6 shrink-0 rounded-full object-cover"
                />
              ) : (
                <ProfileLink
                  userId={userId}
                  username={username}
                  className="inline-flex shrink-0 cursor-pointer transition hover:opacity-90"
                >
                  <div
                    className="h-6 w-6 shrink-0 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40"
                    aria-hidden
                  />
                </ProfileLink>
              )}
              <div className="min-w-0">
                <ProfileUsernameLink
                  userId={userId}
                  username={username}
                  className="text-xs text-gray-400"
                />
                <p className="break-words text-sm text-white">{c.content}</p>
              </div>
            </div>
          )
        })}
    </div>
  )

  const composer = currentUserId ? (
        <div
          className="mt-2 flex gap-2"
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
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
            placeholder="Add a comment…"
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
      </div>
    )
  }

  return (
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
  )
}

type TradeSocialLayerProps = {
  tradeId: string | null | undefined
  currentUserId: string | undefined
  tradeOwnerUserId?: string | null | undefined
  suppressNotifications?: boolean
}

/** Default: engagement row immediately followed by comments panel (legacy stack). */
export default function TradeSocialLayer({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
  suppressNotifications = false,
}: TradeSocialLayerProps) {
  if (!tradeId) return null

  return (
    <div onKeyDown={(e) => e.stopPropagation()}>
      <TradeSocialProvider
        tradeId={tradeId}
        currentUserId={currentUserId}
        tradeOwnerUserId={tradeOwnerUserId}
        suppressNotifications={suppressNotifications}
      >
        <TradeSocialEngagementBar className="mt-3" />
        <TradeSocialCommentsSection />
      </TradeSocialProvider>
    </div>
  )
}
