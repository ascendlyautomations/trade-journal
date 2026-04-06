"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"
import TradeSocialLayer from "../components/TradeSocialLayer"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function postPublicDescription(post: any): string | null {
  const t = post?.trades
  if (!t) return null
  const row = Array.isArray(t) ? t[0] : t
  const raw = row?.public_description
  if (raw == null) return null
  const s = String(raw).trim()
  return s !== "" ? s : null
}

/** Trade owner for notifications (not always same as post author). */
function postTradeOwnerUserId(post: any): string | null | undefined {
  const t = post?.trades
  const row = t ? (Array.isArray(t) ? t[0] : t) : null
  const fromTrade = row?.user_id
  if (fromTrade != null && String(fromTrade).trim() !== "") return String(fromTrade)
  return post?.user_id ?? null
}

type LikeMeta = { count: number; liked: boolean }

export default function FeedPage() {
  const [posts, setPosts] = useState<any[]>([])
  const [user, setUser] = useState<any>(null)
  const [mode, setMode] = useState<"global" | "following">("global")
  const [openComments, setOpenComments] = useState<Record<string, boolean>>({})
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentDraft, setCommentDraft] = useState<Record<string, string>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})
  const [selectedPost, setSelectedPost] = useState<any>(null)

  useEffect(() => {
    fetchUser()
  }, [])

  useEffect(() => {
    if (user) fetchPosts()
  }, [user, mode])

  useEffect(() => {
    if (selectedPost) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
  }, [selectedPost])

  async function fetchUser() {
    const { data } = await supabase.auth.getSession()
    setUser(data.session?.user)
  }

  const loadEngagementForPosts = useCallback(async (postList: any[], currentUser: any) => {
    if (!postList.length) {
      setLikesByPost({})
      setCommentsByPost({})
      return
    }

    const ids = postList.map((p) => p.id)

    const [
      { data: likesRows },
      { data: commentsRows },
      { count: likesExactCount },
    ] = await Promise.all([
      supabase.from("likes").select("post_id, user_id").in("post_id", ids),
      supabase
        .from("comments")
        .select("*, profiles(username)")
        .in("post_id", ids)
        .order("created_at", { ascending: true }),
      supabase
        .from("likes")
        .select("*", { count: "exact", head: true })
        .in("post_id", ids),
    ])
    void likesExactCount

    const likesMap: Record<string, LikeMeta> = {}
    for (const id of ids) {
      const key = String(id)
      likesMap[key] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const pid = String(row.post_id)
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (currentUser && row.user_id === currentUser.id) likesMap[pid].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) {
      commentsMap[String(id)] = []
    }
    for (const c of commentsRows || []) {
      const pid = String(c.post_id)
      if (!commentsMap[pid]) commentsMap[pid] = []
      commentsMap[pid].push(c)
    }

    setLikesByPost(likesMap)
    setCommentsByPost(commentsMap)

    const enriched = postList.map((p) => {
      const key = String(p.id)
      return {
        ...p,
        likesCount: likesMap[key]?.count ?? 0,
        comments: commentsMap[key] ?? [],
      }
    })
    setPosts(enriched)
  }, [])

  async function fetchPosts() {
    if (!user) return

    let list: any[] = []

    if (mode === "global") {
      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url), trades(public_description, user_id)")
        .order("created_at", { ascending: false })

      list = data || []
      setPosts(list)
    }

    if (mode === "following") {
      const { data: following } = await supabase
        .from("followers")
        .select("following_id")
        .eq("follower_id", user.id)

      const ids = following?.map((f) => f.following_id) || []

      if (ids.length === 0) {
        setPosts([])
        setLikesByPost({})
        setCommentsByPost({})
        return
      }

      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url), trades(public_description, user_id)")
        .in("user_id", ids)
        .order("created_at", { ascending: false })

      list = data || []
      setPosts(list)
    }

    await loadEngagementForPosts(list, user)
  }

  async function toggleLike(post: any) {
    if (!user) return

    const pid = String(post.id)
    const meta = likesByPost[pid] || { count: 0, liked: false }

    if (meta.liked) {
      const { error } = await supabase
        .from("likes")
        .delete()
        .eq("post_id", pid)
        .eq("user_id", user.id)

      if (error) {
        console.error("Unlike error:", error)
        return
      }

      const newCount = Math.max(0, meta.count - 1)
      setLikesByPost((prev) => ({
        ...prev,
        [pid]: { count: newCount, liked: false },
      }))
      setPosts((prev) =>
        prev.map((p) =>
          String(p.id) === pid ? { ...p, likesCount: newCount } : p
        )
      )
      setSelectedPost((prev: any) =>
        prev && String(prev.id) === pid ? { ...prev, likesCount: newCount } : prev
      )
    } else {
      const { error } = await supabase.from("likes").insert({
        post_id: pid,
        user_id: user.id,
      })

      if (error) {
        console.error("Like error:", error)
        return
      }

      const newCount = meta.count + 1
      setLikesByPost((prev) => ({
        ...prev,
        [pid]: { count: newCount, liked: true },
      }))
      setPosts((prev) =>
        prev.map((p) =>
          String(p.id) === pid ? { ...p, likesCount: newCount } : p
        )
      )
      setSelectedPost((prev: any) =>
        prev && String(prev.id) === pid ? { ...prev, likesCount: newCount } : prev
      )

      const notifyUserId = postTradeOwnerUserId(post)
      const tradeId = post.trade_id
      if (tradeId && notifyUserId && notifyUserId !== user.id) {
        const { error: nErr } = await supabase.from("notifications").insert({
          user_id: notifyUserId,
          sender_id: user.id,
          type: "like",
          trade_id: tradeId,
        })
        if (nErr) {
          console.error("Notification error:", nErr?.message, nErr)
        } else {
          window.dispatchEvent(new CustomEvent("notification-update"))
          window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
        }
      }
    }
  }

  async function submitComment(post: any) {
    if (!user) return

    const pid = String(post.id)
    const text = (commentDraft[pid] || "").trim()
    if (!text) return

    setCommentSubmitting((s) => ({ ...s, [pid]: true }))

    const { data: newRow, error } = await supabase
      .from("comments")
      .insert({
        post_id: pid,
        user_id: user.id,
        content: text,
      })
      .select("*, profiles(username)")
      .single()

    setCommentSubmitting((s) => ({ ...s, [pid]: false }))

    if (error) {
      console.error("Comment insert error:", error)
      return
    }

    setCommentsByPost((prev) => {
      const next = [...(prev[pid] || []), newRow]
      setPosts((postsPrev) =>
        postsPrev.map((p) =>
          String(p.id) === pid ? { ...p, comments: next } : p
        )
      )
      setSelectedPost((prevSel: any) =>
        prevSel && String(prevSel.id) === pid
          ? { ...prevSel, comments: next }
          : prevSel
      )
      return { ...prev, [pid]: next }
    })
    setCommentDraft((d) => ({ ...d, [pid]: "" }))

    const notifyUserId = postTradeOwnerUserId(post)
    const tradeId = post.trade_id
    if (tradeId && notifyUserId && notifyUserId !== user.id) {
      const { error: nErr } = await supabase.from("notifications").insert({
        user_id: notifyUserId,
        sender_id: user.id,
        type: "comment",
        trade_id: tradeId,
      })
      if (nErr) {
        console.error("Notification error:", nErr?.message, nErr)
      } else {
        window.dispatchEvent(new CustomEvent("notification-update"))
        window.dispatchEvent(new CustomEvent("tj-unread-notifications-refresh"))
      }
    }
  }

  const modalPid = selectedPost ? String(selectedPost.id) : null
  const modalLikesCount = modalPid
    ? likesByPost[modalPid]?.count ?? selectedPost?.likesCount ?? 0
    : 0
  const modalComments = modalPid
    ? commentsByPost[modalPid] ?? selectedPost?.comments ?? []
    : []
  const modalPublicDesc = selectedPost
    ? postPublicDescription(selectedPost)
    : null

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
      <Navbar />

      <div className="flex justify-center px-4 py-6 sm:py-8 pb-10">
        <div className="w-full max-w-xl space-y-6">
          {/* TOGGLE */}
          <div className="flex justify-center gap-3 sm:gap-4 flex-wrap">
            <button
              onClick={() => setMode("global")}
              className={`px-4 py-2 rounded-xl text-sm font-medium transition-colors ${
                mode === "global"
                  ? "bg-blue-500 text-white shadow-lg shadow-blue-500/20"
                  : "bg-white/5 border border-white/10 hover:bg-white/10"
              }`}
            >
              Global
            </button>

            <button
              onClick={() => setMode("following")}
              className={`px-4 py-2 rounded-xl text-sm font-medium transition-colors ${
                mode === "following"
                  ? "bg-blue-500 text-white shadow-lg shadow-blue-500/20"
                  : "bg-white/5 border border-white/10 hover:bg-white/10"
              }`}
            >
              Following
            </button>
          </div>

          {/* POSTS */}
          {posts.map((post) => {
            const imageSrc = postImageSrc(post.image_url)
            const pnl = Number(post.pnl)
            const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
            const pid = String(post.id)
            const likeMeta = likesByPost[pid] || { count: 0, liked: false }
            const comments = commentsByPost[pid] || []
            const publicDesc = postPublicDescription(post)

            return (
              <article
                key={post.id}
                role="button"
                tabIndex={0}
                onClick={() => setSelectedPost(post)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault()
                    setSelectedPost(post)
                  }
                }}
                className="bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20 cursor-pointer transition-all duration-200 hover:border-white/20 hover:shadow-xl hover:bg-white/[0.07]"
              >
                {/* HEADER */}
                <Link
                  href={`/profile/${post.user_id}`}
                  onClick={(e) => e.stopPropagation()}
                  className="flex items-center gap-3 p-4 border-b border-white/5 hover:bg-white/5 transition-colors"
                >
                  {post.profiles?.avatar_url ? (
                    <img
                      src={post.profiles.avatar_url}
                      alt=""
                      className="w-10 h-10 rounded-full object-cover ring-2 ring-white/10 shrink-0"
                    />
                  ) : (
                    <div
                      className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40 ring-2 ring-white/10 shrink-0"
                      aria-hidden
                    />
                  )}
                  <span className="font-semibold text-sm sm:text-base truncate text-white">
                    {post.profiles?.username || "User"}
                  </span>
                </Link>

                {/* IMAGE — only when we have a resolvable path/URL */}
                {imageSrc ? (
                  <div className="w-full bg-black/30">
                    <img
                      src={imageSrc}
                      alt=""
                      className="w-full max-h-[400px] object-cover block"
                    />
                  </div>
                ) : null}

                {/* STATS + public description (notes never shown on feed) */}
                <div className="p-4 space-y-3">
                  <div className="flex justify-between items-center text-sm gap-4">
                    <span
                      className={`font-semibold tabular-nums ${
                        pnlPositive ? "text-emerald-400" : "text-red-400"
                      }`}
                    >
                      {Number.isNaN(pnl) ? "—" : `${pnlPositive ? "+" : ""}$${pnl}`}
                    </span>
                    <span className="text-gray-300 tabular-nums shrink-0">
                      RR {post.rr != null && post.rr !== "" ? post.rr : "—"}
                    </span>
                  </div>

                  {publicDesc && (
                    <div className="mt-2 px-1">
                      <p className="text-white text-sm leading-relaxed">
                        {publicDesc}
                      </p>
                    </div>
                  )}

                  {post.trade_id ? (
                    <div
                      onClick={(e) => e.stopPropagation()}
                      onKeyDown={(e) => e.stopPropagation()}
                    >
                      <TradeSocialLayer
                        tradeId={post.trade_id}
                        currentUserId={user?.id}
                        tradeOwnerUserId={postTradeOwnerUserId(post)}
                      />
                    </div>
                  ) : null}

                  {/* LIKE + COMMENT ACTIONS */}
                  <div
                    className="flex flex-col gap-2 pt-1 border-t border-white/5"
                    onClick={(e) => e.stopPropagation()}
                    onKeyDown={(e) => e.stopPropagation()}
                  >
                    <div className="flex items-center gap-4">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation()
                          toggleLike(post)
                        }}
                        disabled={!user}
                        className="flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"
                        aria-label={likeMeta.liked ? "Unlike" : "Like"}
                      >
                        <span className="text-lg leading-none" aria-hidden>
                          {likeMeta.liked ? "❤️" : "🤍"}
                        </span>
                        <span className="tabular-nums">{likeMeta.count}</span>
                      </button>
                    </div>

                    <button
                      type="button"
                      onClick={(e) => {
                        e.stopPropagation()
                        setOpenComments((prev) => ({
                          ...prev,
                          [post.id]: !prev[post.id],
                        }))
                      }}
                      className="text-left text-sm text-gray-400 hover:text-gray-200"
                    >
                      {openComments[post.id]
                        ? "Hide comments"
                        : `View comments (${comments.length})`}
                    </button>

                    {openComments[post.id] ? (
                      <div className="space-y-3 pt-1">
                        <ul className="max-h-40 overflow-y-auto space-y-2 text-xs text-gray-400 pr-1">
                          {comments.map((c: any) => (
                            <li key={c.id} className="leading-relaxed">
                              <span className="font-medium text-gray-300">
                                {c.profiles?.username || "User"}
                              </span>{" "}
                              <span className="break-words">{c.content}</span>
                            </li>
                          ))}
                        </ul>

                        {user ? (
                          <div
                            className="flex flex-col sm:flex-row gap-2"
                            onClick={(e) => e.stopPropagation()}
                            onKeyDown={(e) => e.stopPropagation()}
                          >
                            <input
                              id={`comment-input-${pid}`}
                              type="text"
                              placeholder="Add a comment…"
                              value={commentDraft[pid] || ""}
                              onChange={(e) =>
                                setCommentDraft((d) => ({ ...d, [pid]: e.target.value }))
                              }
                              onClick={(e) => e.stopPropagation()}
                              onFocus={(e) => e.stopPropagation()}
                              onKeyDown={(e) => {
                                e.stopPropagation()
                                if (e.key === "Enter" && !e.shiftKey) {
                                  e.preventDefault()
                                  submitComment(post)
                                }
                              }}
                              className="flex-1 min-w-0 px-3 py-2 rounded-lg bg-[#0f172a]/80 border border-white/10 text-sm text-white placeholder:text-gray-500"
                            />
                            <button
                              type="button"
                              disabled={
                                commentSubmitting[pid] || !(commentDraft[pid] || "").trim()
                              }
                              onClick={(e) => {
                                e.stopPropagation()
                                submitComment(post)
                              }}
                              className="px-4 py-2 rounded-lg text-sm font-medium bg-blue-500/90 hover:bg-blue-500 text-white disabled:opacity-40 shrink-0"
                            >
                              {commentSubmitting[pid] ? "…" : "Post"}
                            </button>
                          </div>
                        ) : null}
                      </div>
                    ) : null}
                  </div>
                </div>
              </article>
            )
          })}
        </div>
      </div>

      {selectedPost && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
          onClick={() => setSelectedPost(null)}
        >
          <div
            className="relative w-full max-w-2xl rounded-xl bg-[#0f172a] p-4"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setSelectedPost(null)}
              className="absolute right-2 top-2 text-xl text-white"
              aria-label="Close"
            >
              ✕
            </button>

            {selectedPost.image_url ? (
              <img
                src={
                  String(selectedPost.image_url).startsWith("http")
                    ? selectedPost.image_url
                    : `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${selectedPost.image_url}`
                }
                alt=""
                className="w-full max-h-[400px] rounded-lg object-cover"
              />
            ) : null}

            <div className="mt-3 space-y-2 text-sm">
              <div className="flex justify-between">
                <span
                  className={
                    Number(selectedPost.pnl) >= 0
                      ? "text-green-400"
                      : "text-red-400"
                  }
                >
                  ${selectedPost.pnl}
                </span>
                <span>RR {selectedPost.rr}</span>
              </div>

              <div className="flex justify-between text-gray-300">
                <span>Points: {selectedPost.points || "-"}</span>
                <span>Account: {selectedPost.account_type || "-"}</span>
              </div>
            </div>

            {modalPublicDesc && (
              <div className="mt-2 px-1">
                <p className="text-white text-sm leading-relaxed">
                  {modalPublicDesc}
                </p>
              </div>
            )}

            {selectedPost.trade_id ? (
              <div className="mt-3">
                <TradeSocialLayer
                  tradeId={selectedPost.trade_id}
                  currentUserId={user?.id}
                  tradeOwnerUserId={postTradeOwnerUserId(selectedPost)}
                />
              </div>
            ) : null}

            <div className="mt-3 text-sm text-gray-300">
              ❤️ {modalLikesCount || selectedPost.likesCount || 0} likes
            </div>

            <div className="mt-2 max-h-40 space-y-1 overflow-y-auto">
              {(modalComments.length
                ? modalComments
                : selectedPost.comments || []
              ).map((c: any) => (
                <div key={c.id} className="text-sm">
                  <span className="font-semibold">
                    {c.profiles?.username || "User"}
                  </span>{" "}
                  {c.content}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
