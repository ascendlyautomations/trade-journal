"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

type LikeMeta = { count: number; liked: boolean }

export default function FeedPage() {
  const [posts, setPosts] = useState<any[]>([])
  const [user, setUser] = useState<any>(null)
  const [mode, setMode] = useState<"global" | "following">("global")
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentDraft, setCommentDraft] = useState<Record<string, string>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})

  useEffect(() => {
    fetchUser()
  }, [])

  useEffect(() => {
    if (user) fetchPosts()
  }, [user, mode])

  async function fetchUser() {
    const { data } = await supabase.auth.getSession()
    setUser(data.session?.user)
  }

  const loadEngagementForPosts = useCallback(async (postList: any[], currentUser: any) => {
    if (!currentUser || !postList.length) {
      setLikesByPost({})
      setCommentsByPost({})
      return
    }

    const ids = postList.map((p) => p.id)

    const [{ data: likesRows }, { data: commentsRows }] = await Promise.all([
      supabase.from("likes").select("post_id, user_id").in("post_id", ids),
      supabase
        .from("comments")
        .select("*, profiles(username)")
        .in("post_id", ids)
        .order("created_at", { ascending: true }),
    ])

    const likesMap: Record<string, LikeMeta> = {}
    for (const id of ids) {
      likesMap[id] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const pid = row.post_id as string
      if (!likesMap[pid]) likesMap[pid] = { count: 0, liked: false }
      likesMap[pid].count++
      if (row.user_id === currentUser.id) likesMap[pid].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) commentsMap[id] = []
    for (const c of commentsRows || []) {
      const pid = c.post_id as string
      if (!commentsMap[pid]) commentsMap[pid] = []
      commentsMap[pid].push(c)
    }

    setLikesByPost(likesMap)
    setCommentsByPost(commentsMap)
  }, [])

  async function fetchPosts() {
    if (!user) return

    let list: any[] = []

    if (mode === "global") {
      const { data } = await supabase
        .from("posts")
        .select("*, profiles(username, avatar_url)")
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
        .select("*, profiles(username, avatar_url)")
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

      setLikesByPost((prev) => ({
        ...prev,
        [pid]: { count: Math.max(0, meta.count - 1), liked: false },
      }))
    } else {
      const { error } = await supabase.from("likes").insert({
        post_id: pid,
        user_id: user.id,
      })

      if (error) {
        console.error("Like error:", error)
        return
      }

      setLikesByPost((prev) => ({
        ...prev,
        [pid]: { count: meta.count + 1, liked: true },
      }))

      if (post.user_id && post.user_id !== user.id) {
        const { error: nErr } = await supabase.from("notifications").insert({
          user_id: post.user_id,
          sender_id: user.id,
          type: "like",
          post_id: pid,
        })
        if (nErr) console.error("Notification (like) error:", nErr)
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

    setCommentsByPost((prev) => ({
      ...prev,
      [pid]: [...(prev[pid] || []), newRow],
    }))
    setCommentDraft((d) => ({ ...d, [pid]: "" }))

    if (post.user_id && post.user_id !== user.id) {
      const { error: nErr } = await supabase.from("notifications").insert({
        user_id: post.user_id,
        sender_id: user.id,
        type: "comment",
        post_id: pid,
      })
      if (nErr) console.error("Notification (comment) error:", nErr)
    }
  }

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

            return (
              <article
                key={post.id}
                className="bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20"
              >
                {/* HEADER */}
                <Link
                  href={`/profile/${post.user_id}`}
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

                {/* STATS + CAPTION */}
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

                  {post.caption ? (
                    <p className="text-xs text-gray-400 leading-relaxed whitespace-pre-wrap break-words">
                      {post.caption}
                    </p>
                  ) : null}

                  {/* LIKE + COMMENT ACTIONS */}
                  <div className="flex items-center gap-4 pt-1 border-t border-white/5">
                    <button
                      type="button"
                      onClick={() => toggleLike(post)}
                      disabled={!user}
                      className="flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"
                      aria-label={likeMeta.liked ? "Unlike" : "Like"}
                    >
                      <span className="text-lg leading-none" aria-hidden>
                        {likeMeta.liked ? "❤️" : "🤍"}
                      </span>
                      <span className="tabular-nums">{likeMeta.count}</span>
                    </button>

                    <button
                      type="button"
                      onClick={() =>
                        document.getElementById(`comment-input-${pid}`)?.focus()
                      }
                      className="flex items-center gap-1.5 text-sm text-gray-400 hover:text-gray-200"
                      aria-label="Comment"
                    >
                      <span className="text-lg leading-none" aria-hidden>
                        💬
                      </span>
                      <span className="tabular-nums">{comments.length}</span>
                    </button>
                  </div>

                  {/* COMMENTS */}
                  {comments.length > 0 ? (
                    <ul className="space-y-2 text-xs text-gray-400">
                      {comments.map((c: any) => (
                        <li key={c.id} className="leading-relaxed">
                          <span className="font-medium text-gray-300">
                            {c.profiles?.username || "User"}
                          </span>{" "}
                          <span className="break-words">{c.content}</span>
                        </li>
                      ))}
                    </ul>
                  ) : null}

                  {user ? (
                    <div className="flex flex-col sm:flex-row gap-2">
                      <input
                        id={`comment-input-${pid}`}
                        type="text"
                        placeholder="Add a comment…"
                        value={commentDraft[pid] || ""}
                        onChange={(e) =>
                          setCommentDraft((d) => ({ ...d, [pid]: e.target.value }))
                        }
                        onKeyDown={(e) => {
                          if (e.key === "Enter" && !e.shiftKey) {
                            e.preventDefault()
                            submitComment(post)
                          }
                        }}
                        className="flex-1 min-w-0 px-3 py-2 rounded-lg bg-[#0f172a]/80 border border-white/10 text-sm text-white placeholder:text-gray-500"
                      />
                      <button
                        type="button"
                        disabled={commentSubmitting[pid] || !(commentDraft[pid] || "").trim()}
                        onClick={() => submitComment(post)}
                        className="px-4 py-2 rounded-lg text-sm font-medium bg-blue-500/90 hover:bg-blue-500 text-white disabled:opacity-40 shrink-0"
                      >
                        {commentSubmitting[pid] ? "…" : "Post"}
                      </button>
                    </div>
                  ) : null}
                </div>
              </article>
            )
          })}
        </div>
      </div>
    </div>
  )
}
