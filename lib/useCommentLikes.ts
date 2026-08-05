"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import {
  applyCommentLikeRealtimeEvent,
  fetchCommentLikeMetaByIds,
  toggleCommentLike,
  type CommentLikeMeta,
  type CommentLikeNotificationParent,
  type CommentLikeSource,
} from "@/lib/commentLikes"
import { buildRealtimeInFilter } from "@/lib/realtimeFilters"

export function useCommentLikes(args: {
  source: CommentLikeSource | null
  comments: any[]
  currentUserId: string | null | undefined
  notificationParent: CommentLikeNotificationParent
}) {
  const { source, comments, currentUserId, notificationParent } = args
  const [likesByCommentId, setLikesByCommentId] = useState<
    Record<string, CommentLikeMeta>
  >({})
  const [busyCommentIds, setBusyCommentIds] = useState<Record<string, boolean>>(
    {}
  )
  const likeBusyRef = useRef<Set<string>>(new Set())
  const likesByCommentIdRef = useRef(likesByCommentId)
  likesByCommentIdRef.current = likesByCommentId

  const commentIds = useMemo(
    () => comments.map((comment) => String(comment.id)),
    [comments]
  )
  const commentIdsKey = commentIds.join(",")
  const hasComments = commentIds.length > 0

  const visibleIdsRef = useRef(new Set<string>())
  visibleIdsRef.current = new Set(commentIds)

  const currentUserIdRef = useRef(currentUserId)
  currentUserIdRef.current = currentUserId

  useEffect(() => {
    if (!source || commentIds.length === 0 || isDemoModeActive()) {
      setLikesByCommentId({})
      return
    }

    let cancelled = false
    void fetchCommentLikeMetaByIds(
      supabase,
      source,
      commentIds,
      currentUserId
    ).then((meta) => {
      if (!cancelled) setLikesByCommentId(meta)
    })

    return () => {
      cancelled = true
    }
  }, [source, commentIdsKey, currentUserId, commentIds])

  useEffect(() => {
    if (!source || !hasComments || isDemoModeActive()) return

    const ids = commentIdsKey.split(",").filter(Boolean)
    const idFilter = buildRealtimeInFilter("comment_id", ids)
    // Too many visible comments: keep source-scoped filter (client still gates).
    const filter = idFilter
      ? idFilter
      : `comment_source=eq.${source}`

    const topic = `comment-likes-${source}-${commentIdsKey.slice(0, 48) || "empty"}`
    const channel = supabase.channel(topic)

    channel.on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "comment_likes",
        filter,
      },
      (payload) => {
        const row = (payload.new ?? payload.old) as {
          comment_id?: string
          user_id?: string
          comment_source?: string
        } | null
        if (
          row?.comment_source != null &&
          String(row.comment_source) !== source
        ) {
          return
        }
        const commentId = row?.comment_id != null ? String(row.comment_id) : ""
        const actorUserId = row?.user_id != null ? String(row.user_id) : ""
        if (!commentId || !visibleIdsRef.current.has(commentId)) return
        if (likeBusyRef.current.has(commentId)) return
        if (payload.eventType !== "INSERT" && payload.eventType !== "DELETE") {
          return
        }

        setLikesByCommentId((prev) => {
          const current = prev[commentId] ?? { count: 0, liked: false }
          return {
            ...prev,
            [commentId]: applyCommentLikeRealtimeEvent(
              current,
              payload.eventType as "INSERT" | "DELETE",
              actorUserId,
              currentUserIdRef.current
            ),
          }
        })
      }
    )

    channel.subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [source, hasComments, commentIdsKey])

  const isCommentLikeBusy = useCallback(
    (commentId: string) => Boolean(busyCommentIds[commentId]),
    [busyCommentIds]
  )

  const toggleCommentLikeFor = useCallback(
    async (comment: any) => {
      if (isDemoModeActive()) {
        requestDemoSignup("like")
        return
      }
      if (!source || !currentUserId) return
      const commentId = String(comment.id)
      if (likeBusyRef.current.has(commentId)) return

      const meta =
        likesByCommentIdRef.current[commentId] ?? { count: 0, liked: false }
      const authorUserId =
        comment.user_id != null ? String(comment.user_id) : null

      likeBusyRef.current.add(commentId)
      setBusyCommentIds((prev) => ({ ...prev, [commentId]: true }))
      try {
        await toggleCommentLike(supabase, {
          commentSource: source,
          commentId,
          userId: currentUserId,
          authorUserId,
          meta,
          notificationParent,
          onMetaChange: (next) => {
            setLikesByCommentId((prev) => ({ ...prev, [commentId]: next }))
          },
        })
      } finally {
        likeBusyRef.current.delete(commentId)
        setBusyCommentIds((prev) => {
          const next = { ...prev }
          delete next[commentId]
          return next
        })
      }
    },
    [currentUserId, notificationParent, source]
  )

  return {
    likesByCommentId,
    toggleCommentLikeFor,
    isCommentLikeBusy,
    canLikeComments: Boolean(source && currentUserId),
  }
}
