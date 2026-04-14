"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"

type TradeSocialLayerProps = {
  tradeId: string | null | undefined
  currentUserId: string | undefined
  /** Trade owner; used for notifications (skip if viewer is owner). */
  tradeOwnerUserId?: string | null | undefined
}

export default function TradeSocialLayer({
  tradeId,
  currentUserId,
  tradeOwnerUserId,
}: TradeSocialLayerProps) {
  const [likes, setLikes] = useState(0)
  const [liked, setLiked] = useState(false)
  const [comments, setComments] = useState<any[]>([])
  const [showComments, setShowComments] = useState(false)
  const [newComment, setNewComment] = useState("")

  useEffect(() => {
    if (!tradeId) return

    let cancelled = false

    const fetchData = async () => {
      const { data: likeData } = await supabase
        .from("trade_likes")
        .select("user_id")
        .eq("trade_id", tradeId)

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
        .eq("trade_id", tradeId)
        .order("created_at", { ascending: true })

      if (cancelled) return

      setComments(commentData || [])
    }

    fetchData()

    return () => {
      cancelled = true
    }
  }, [tradeId, currentUserId])

  useEffect(() => {
    if (!tradeId) return

    const topic = `trade-${tradeId}-${crypto.randomUUID()}`
    const channel = supabase.channel(topic)

    // Listen to trade likes.
    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "trade_likes",
        filter: `trade_id=eq.${tradeId}`,
      },
      (payload) => {
        console.log("Like update:", payload)
        void (async () => {
          const { data } = await supabase
            .from("trade_likes")
            .select("user_id")
            .eq("trade_id", tradeId)

          const rows = data || []
          setLikes(rows.length)
          setLiked(
            currentUserId != null &&
              rows.some((l: { user_id: string }) => l.user_id === currentUserId)
          )
        })()
      }
    )

    // Listen to trade comments.
    channel.on(
      "postgres_changes",
      {
        event: "INSERT",
        schema: "public",
        table: "trade_comments",
        filter: `trade_id=eq.${tradeId}`,
      },
      (payload) => {
        console.log("Comment update:", payload)
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

    channel.subscribe((status) => {
      console.log("Realtime status:", status)
    })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [tradeId, currentUserId])

  const handleLike = async () => {
    if (!tradeId || !currentUserId) return

    const { data: existing } = await supabase
      .from("trade_likes")
      .select("id")
      .eq("trade_id", tradeId)
      .eq("user_id", currentUserId)
      .maybeSingle()

    if (existing) {
      const { error } = await supabase
        .from("trade_likes")
        .delete()
        .eq("trade_id", tradeId)
        .eq("user_id", currentUserId)

      if (error) {
        console.error("Unlike trade error:", error)
        return
      }

      setLiked(false)
      setLikes((prev) => Math.max(0, prev - 1))
    } else {
      const { error } = await supabase.from("trade_likes").insert({
        trade_id: tradeId,
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
        trade_id: tradeId,
      })

      if (nErr) {
        console.error("Notification error:", nErr?.message, nErr)
        return
      }

      window.dispatchEvent(new CustomEvent("notification-update"))
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }
  }

  const handleComment = async () => {
    if (!tradeId || !currentUserId || !newComment.trim()) return

    const { data, error } = await supabase
      .from("trade_comments")
      .insert({
        trade_id: tradeId,
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
        trade_id: tradeId,
      })

      if (nErr) {
        console.error("Notification error:", nErr?.message, nErr)
        return
      }

      window.dispatchEvent(new CustomEvent("notification-update"))
      window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
    }
  }

  if (!tradeId) return null

  return (
    <div onKeyDown={(e) => e.stopPropagation()}>
      <div className="mt-3 flex items-center gap-4 text-sm">
        <button
          type="button"
          disabled={!currentUserId}
          onClick={(e) => {
            e.stopPropagation()
            handleLike()
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

      {showComments && (
        <div
          className="mt-3 space-y-2"
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => e.stopPropagation()}
        >
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
                    className="w-6 h-6 rounded-full object-cover shrink-0"
                  />
                ) : (
                  <div
                    className="w-6 h-6 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40 shrink-0"
                    aria-hidden
                  />
                )}
                <div className="min-w-0">
                  <p className="text-xs text-gray-400">
                    {c.profiles?.username || "User"}
                  </p>
                  <p className="text-white text-sm break-words">{c.content}</p>
                </div>
              </div>
            )
          })}

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
                    handleComment()
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
                  handleComment()
                }}
                className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
              >
                Post
              </button>
            </div>
          ) : null}
        </div>
      )}
    </div>
  )
}
