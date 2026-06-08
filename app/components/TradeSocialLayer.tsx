"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import { supabase } from "../../lib/supabaseClient"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
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
  newComment: string
  setNewComment: (value: string) => void
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
  children: ReactNode
}

export function TradeSocialProvider({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
  children,
}: TradeSocialProviderProps) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [likes, setLikes] = useState(0)
  const [liked, setLiked] = useState(false)
  const [comments, setComments] = useState<any[]>([])
  const [showComments, setShowComments] = useState(false)
  const [newComment, setNewComment] = useState("")

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
    if (!resolvedId || !currentUserId) return

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

      const receiverId =
        tradeOwnerUserId != null ? String(tradeOwnerUserId).trim() : ""
      if (!receiverId || receiverId === currentUserId) return

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
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }
  }, [resolvedId, currentUserId, tradeOwnerUserId])

  const handleComment = useCallback(async () => {
    if (!resolvedId || !currentUserId || !newComment.trim()) return

    const userIsPro = await isUserPro(supabase as any, currentUserId)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        currentUserId,
        10
      )
      if (limitReached) {
        showPopup({
          type: "warning",
          message: handleSupabaseError({ message: "10 messages limit" }),
        })
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

      const receiverId =
        tradeOwnerUserId != null ? String(tradeOwnerUserId).trim() : ""
      if (!receiverId || receiverId === currentUserId) return

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
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }
  }, [resolvedId, currentUserId, newComment, tradeOwnerUserId, showPopup])

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
      newComment,
      setNewComment,
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
    newComment,
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
  const { liked, likes, comments, showComments, setShowComments, handleLike, currentUserId } =
    useTradeSocial()

  return (
    <div className={`flex items-center gap-4 text-sm ${className}`}>
      <button
        type="button"
        disabled={!currentUserId}
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
          setShowComments(!showComments)
        }}
        className="text-gray-400 hover:text-gray-200"
      >
        💬 {comments.length}
      </button>
    </div>
  )
}

/** Comment list + composer; renders nothing when `showComments` is false. */
export function TradeSocialCommentsSection({
  className = "",
}: {
  className?: string
}) {
  const {
    showComments,
    comments,
    newComment,
    setNewComment,
    handleComment,
    currentUserId,
  } = useTradeSocial()

  if (!showComments) return null

  return (
    <div
      className={`space-y-3 border-t border-white/10 mt-2 pt-3 ${className}`}
      onClick={(e) => e.stopPropagation()}
      onKeyDown={(e) => e.stopPropagation()}
    >
      <div className="space-y-2">
        {comments.map((c) => {
          const av = c.profiles?.avatar_url
          const hasAv =
            av != null && String(av).trim() !== "" && String(av) !== "null"
          return (
            <div key={c.id} className="flex gap-2 items-start">
              {hasAv ? (
                <img
                  src={String(av).trim()}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="w-6 h-6 rounded-full object-cover shrink-0"
                />
              ) : (
                <div
                  className="w-6 h-6 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40 shrink-0"
                  aria-hidden
                />
              )}
              <div className="min-w-0">
                <p className="text-xs text-gray-400">{c.profiles?.username || "User"}</p>
                <p className="text-white text-sm break-words">{c.content}</p>
              </div>
            </div>
          )
        })}
      </div>

      {currentUserId ? (
        <div
          className="flex gap-2 mt-2"
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
            className="flex-1 min-w-0 p-2 bg-[#1e293b] text-white rounded-lg border border-gray-600 text-sm placeholder:text-gray-500"
          />

          <button
            type="button"
            disabled={!newComment.trim()}
            onClick={(e) => {
              e.stopPropagation()
              void handleComment()
            }}
            className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
          >
            Post
          </button>
        </div>
      ) : null}
    </div>
  )
}

type TradeSocialLayerProps = {
  tradeId: string | null | undefined
  currentUserId: string | undefined
  tradeOwnerUserId?: string | null | undefined
}

/** Default: engagement row immediately followed by comments panel (legacy stack). */
export default function TradeSocialLayer({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
}: TradeSocialLayerProps) {
  if (!tradeId) return null

  return (
    <div onKeyDown={(e) => e.stopPropagation()}>
      <TradeSocialProvider
        tradeId={tradeId}
        currentUserId={currentUserId}
        tradeOwnerUserId={tradeOwnerUserId}
      >
        <TradeSocialEngagementBar className="mt-3" />
        <TradeSocialCommentsSection />
      </TradeSocialProvider>
    </div>
  )
}
