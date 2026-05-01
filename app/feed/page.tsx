"use client"

import Link from "next/link"
import type { ChangeEvent } from "react"
import { useCallback, useEffect, useRef, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { fetchShareConversations } from "@/lib/shareToConversations"
import { formatEST } from "@/lib/formatEST"
import { isUserPro, reachedMessagesCommentsLimit } from "@/lib/freePlanLimits"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import Navbar from "../components/Navbar"
import {
  PostInteractionsComments,
  PostInteractionsEngagement,
} from "../components/PostInteractions"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

const STORY_WINDOW_MS = 24 * 60 * 60 * 1000
/** Auto-advance each slide (Instagram-style). */
const STORY_SLIDE_MS = 7000

type StoryRow = {
  id: string
  user_id: string
  image_url: string
  created_at: string
}

type StoryBarProfile = {
  id: string
  username?: string | null
  avatar_url?: string | null
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

function postTradeJoin(post: any) {
  const t = post?.trades
  if (!t) return null
  return Array.isArray(t) ? t[0] : t
}

function getModeStyles(mode: string | null | undefined): string {
  if (!mode) return ""
  const m = mode.toLowerCase()
  if (m === "funded") return "bg-green-500/20 text-green-300"
  if (m === "eval") return "bg-yellow-500/20 text-yellow-300"
  if (m === "live") return "bg-blue-500/20 text-blue-300"
  return "bg-white/10 text-gray-300"
}

type LikeMeta = { count: number; liked: boolean }

export default function FeedPage() {
  const [posts, setPosts] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const pageRef = useRef(0)
  const loadingRef = useRef(false)
  const hasMoreRef = useRef(true)
  const [user, setUser] = useState<any>(null)
  const [mode, setMode] = useState<"global" | "following">("following")
  const [openComments, setOpenComments] = useState<Record<string, boolean>>({})
  const [likesByPost, setLikesByPost] = useState<Record<string, LikeMeta>>({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentDraft, setCommentDraft] = useState<Record<string, string>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<Record<string, boolean>>({})
  const [selectedPost, setSelectedPost] = useState<any>(null)
  const [sharePost, setSharePost] = useState<any>(null)
  const [shareMessage, setShareMessage] = useState("")
  const [shareConversations, setShareConversations] = useState<any[]>([])
  const [selectedConversations, setSelectedConversations] = useState<string[]>([])
  const [shareLoading, setShareLoading] = useState(false)
  const [storiesByUser, setStoriesByUser] = useState<Record<string, StoryRow[]>>(
    {}
  )
  const [users, setUsers] = useState<StoryBarProfile[]>([])
  const [activeStoryUser, setActiveStoryUser] = useState<string | null>(null)
  const [currentStoryIndex, setCurrentStoryIndex] = useState(0)

  const currentStories = activeStoryUser
    ? (storiesByUser[activeStoryUser] ?? [])
    : []
  const currentStory = currentStories[currentStoryIndex]

  useEffect(() => {
    fetchUser()
  }, [])

  const loadFollowingStories = useCallback(async () => {
    if (!user?.id) return

    const { data: following } = await supabase
      .from("followers")
      .select("following_id")
      .eq("follower_id", user.id)

    const followingIds = [
      ...new Set(
        (following ?? [])
          .map((f) => f.following_id)
          .filter((id): id is string => id != null && String(id).trim() !== "")
      ),
    ]

    const storyUserIds = [...new Set([...followingIds, user.id])]

    const { data: stories, error: storiesErr } = await supabase
      .from("stories")
      .select("*")
      .in("user_id", storyUserIds)
      .order("created_at", { ascending: false })

    if (storiesErr) {
      console.error("stories fetch:", storiesErr)
      setStoriesByUser({})
      setUsers([])
      return
    }

    const now = Date.now()
    const recentStories = (stories ?? []).filter((story) => {
      const created = new Date(story.created_at).getTime()
      return !Number.isNaN(created) && now - created < STORY_WINDOW_MS
    })

    const storiesByUserMap: Record<string, StoryRow[]> = {}
    for (const story of recentStories) {
      const uid = String(story.user_id)
      if (!storiesByUserMap[uid]) storiesByUserMap[uid] = []
      storiesByUserMap[uid].push(story as StoryRow)
    }

    for (const uid of Object.keys(storiesByUserMap)) {
      storiesByUserMap[uid].sort(
        (a, b) =>
          new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      )
    }

    const userIds = Object.keys(storiesByUserMap)
    if (userIds.length === 0) {
      setStoriesByUser({})
      setUsers([])
      return
    }

    const { data: profiles, error: profilesErr } = await supabase
      .from("profiles")
      .select("id, username, avatar_url")
      .in("id", userIds)

    if (profilesErr) {
      console.error("story bar profiles:", profilesErr)
      setStoriesByUser(storiesByUserMap)
      setUsers([])
      return
    }

    const list = (profiles ?? []) as StoryBarProfile[]
    const latest = (id: string) =>
      new Date(storiesByUserMap[id][0].created_at).getTime()

    list.sort((a, b) => latest(b.id) - latest(a.id))

    setStoriesByUser(storiesByUserMap)
    setUsers(list)
  }, [user])

  useEffect(() => {
    if (!user || mode !== "following") {
      setStoriesByUser({})
      setUsers([])
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
      return
    }

    void loadFollowingStories()
  }, [user, mode, loadFollowingStories])

  const handleStoryUpload = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      const input = e.target
      const file = input.files?.[0]
      input.value = ""
      if (!file || !user?.id) return

      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }
      const fileName = `${user.id}/${Date.now()}-${uploadFile.name}`

      const { error: uploadError } = await supabase.storage
        .from("stories")
        .upload(fileName, uploadFile, { upsert: true })

      if (uploadError) {
        console.error(uploadError)
        alert(uploadError.message)
        return
      }

      const base = process.env.NEXT_PUBLIC_SUPABASE_URL
      if (!base) {
        alert("Missing NEXT_PUBLIC_SUPABASE_URL")
        return
      }

      const publicUrl = `${base}/storage/v1/object/public/stories/${fileName}`

      const { error: insertError } = await supabase.from("stories").insert({
        user_id: user.id,
        image_url: publicUrl,
      })

      if (insertError) {
        console.error(insertError)
        alert(handleSupabaseError(insertError))
        return
      }

      alert("Story uploaded!")
      await loadFollowingStories()
    },
    [user, loadFollowingStories]
  )

  const openStory = useCallback((userId: string) => {
    setActiveStoryUser(userId)
    setCurrentStoryIndex(0)
  }, [])

  const nextStory = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex < list.length - 1) {
      setCurrentStoryIndex((prev) => prev + 1)
      return
    }

    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex >= 0 && currentUserIndex < userIds.length - 1) {
      const nextUser = userIds[currentUserIndex + 1]
      setActiveStoryUser(nextUser)
      setCurrentStoryIndex(0)
    } else {
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser, users])

  const prevStory = useCallback(() => {
    const list = activeStoryUser
      ? (storiesByUser[activeStoryUser] ?? [])
      : []

    if (currentStoryIndex > 0) {
      setCurrentStoryIndex((prev) => prev - 1)
      return
    }

    const userIds = users.map((u) => u.id)
    const currentUserIndex = activeStoryUser
      ? userIds.indexOf(activeStoryUser)
      : -1

    if (currentUserIndex > 0) {
      const prevUser = userIds[currentUserIndex - 1]
      const prevUserStories = storiesByUser[prevUser] ?? []

      setActiveStoryUser(prevUser)
      setCurrentStoryIndex(Math.max(0, prevUserStories.length - 1))
    }
  }, [activeStoryUser, currentStoryIndex, storiesByUser, users])

  useEffect(() => {
    if (!activeStoryUser) return
    const list = storiesByUser[activeStoryUser] ?? []
    if (list.length === 0) {
      setActiveStoryUser(null)
      setCurrentStoryIndex(0)
      return
    }
    if (currentStoryIndex >= list.length) {
      setCurrentStoryIndex(Math.max(0, list.length - 1))
    }
  }, [activeStoryUser, storiesByUser, currentStoryIndex])

  useEffect(() => {
    if (!activeStoryUser) return
    const list = storiesByUser[activeStoryUser] ?? []
    if (list.length === 0) return

    const timer = window.setTimeout(() => {
      nextStory()
    }, STORY_SLIDE_MS)

    return () => clearTimeout(timer)
  }, [activeStoryUser, currentStoryIndex, storiesByUser, nextStory])

  useEffect(() => {
    if (!activeStoryUser) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setActiveStoryUser(null)
        setCurrentStoryIndex(0)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [activeStoryUser])

  useEffect(() => {
    if (selectedPost || activeStoryUser) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
    document.body.style.overflow = ""
    return undefined
  }, [selectedPost, activeStoryUser])

  async function fetchUser() {
    const { data } = await supabase.auth.getSession()
    setUser(data.session?.user)
  }

  const loadEngagementForPosts = useCallback(async (postList: any[], currentUser: any) => {
    if (!postList.length) {
      return {
        enriched: [] as any[],
        likesMap: {} as Record<string, LikeMeta>,
        commentsMap: {} as Record<string, any[]>,
      }
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
        .select("*, profiles(username, avatar_url)")
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

    const enriched = postList.map((p) => {
      const key = String(p.id)
      return {
        ...p,
        likesCount: likesMap[key]?.count ?? 0,
      }
    })
    return { enriched, likesMap, commentsMap }
  }, [])

  const loadPosts = useCallback(
    async (pageOverride?: number) => {
      if (!user || loadingRef.current || !hasMoreRef.current) return

      const currentPage = pageOverride ?? pageRef.current
      const from = currentPage * 8
      const to = from + 7

      setLoading(true)
      loadingRef.current = true

      let list: any[] = []

      if (mode === "global") {
        const { data, error } = await supabase
          .from("posts")
          .select(
            "*, profiles(id, username, avatar_url), trades(public_description, user_id, ticker, direction, account_type, points)"
          )
          .order("created_at", { ascending: false })
          .range(from, to)

        if (error) {
          console.error(error)
          loadingRef.current = false
          setLoading(false)
          return
        }

        list = data || []
      }

      if (mode === "following") {
        const { data: following, error: followingError } = await supabase
          .from("followers")
          .select("following_id")
          .eq("follower_id", user.id)

        if (followingError) {
          console.error(followingError)
          loadingRef.current = false
          setLoading(false)
          return
        }

        const ids = following?.map((f) => f.following_id) || []

        if (ids.length === 0) {
          hasMoreRef.current = false
          setHasMore(false)
          loadingRef.current = false
          setLoading(false)
          return
        }

        const { data, error } = await supabase
          .from("posts")
          .select(
            "*, profiles(id, username, avatar_url), trades(public_description, user_id, ticker, direction, account_type, points)"
          )
          .in("user_id", ids)
          .order("created_at", { ascending: false })
          .range(from, to)

        if (error) {
          console.error(error)
          loadingRef.current = false
          setLoading(false)
          return
        }

        list = data || []
      }

      console.log("FEED TRADE SAMPLE:", list?.[0])

      if (list.length < 8) {
        hasMoreRef.current = false
        setHasMore(false)
      }

      const { enriched, likesMap, commentsMap } = await loadEngagementForPosts(list, user)

      setPosts((prev) => [...prev, ...enriched])
      setLikesByPost((prev) => ({ ...prev, ...likesMap }))
      setCommentsByPost((prev) => ({ ...prev, ...commentsMap }))
      const nextPage = pageOverride != null ? pageOverride + 1 : pageRef.current + 1
      pageRef.current = nextPage
      setPage(nextPage)
      loadingRef.current = false
      setLoading(false)
    },
    [user, mode, loadEngagementForPosts]
  )

  useEffect(() => {
    if (!user) return
    setPosts([])
    setLikesByPost({})
    setCommentsByPost({})
    setPage(0)
    setHasMore(true)
    setLoading(false)
    pageRef.current = 0
    hasMoreRef.current = true
    loadingRef.current = false
    void loadPosts(0)
  }, [user, mode, loadPosts])

  useEffect(() => {
    const handleScroll = () => {
      if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 200) {
        void loadPosts()
      }
    }

    window.addEventListener("scroll", handleScroll)
    return () => window.removeEventListener("scroll", handleScroll)
  }, [loadPosts])

  useEffect(() => {
    if (!sharePost || !user?.id) return

    const loadShareConversations = async () => {
      setShareLoading(true)
      const list = await fetchShareConversations(supabase, user.id)
      setShareConversations(list)
      setShareLoading(false)
    }

    void loadShareConversations()
  }, [sharePost, user?.id])

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

    const userIsPro = await isUserPro(supabase as any, user.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        user.id,
        10
      )
      if (limitReached) {
        alert(handleSupabaseError({ message: "10 messages limit" }))
        return
      }
    }

    setCommentSubmitting((s) => ({ ...s, [pid]: true }))

    const { data: newRow, error } = await supabase
      .from("comments")
      .insert({
        post_id: pid,
        user_id: user.id,
        content: text,
      })
      .select("*, profiles(username, avatar_url)")
      .single()

    setCommentSubmitting((s) => ({ ...s, [pid]: false }))

    if (error) {
      console.error("Comment insert error:", error)
      alert(handleSupabaseError(error))
      return
    }

    const currentComments = commentsByPost[pid] || []
    const nextComments = currentComments.some((c: any) => c.id === newRow.id)
      ? currentComments
      : [...currentComments, newRow]
    updateComments(pid, nextComments)
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

  const updateComments = (postId: string, newComments: any[]) => {
    setCommentsByPost((prev) => ({
      ...prev,
      [postId]: newComments,
    }))
  }

  const toggleConversation = (id: string) => {
    setSelectedConversations((prev) =>
      prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]
    )
  }

  const handleSendPost = async () => {
    if (!sharePost || selectedConversations.length === 0) return

    const {
      data: { user: authUser },
    } = await supabase.auth.getUser()

    if (!authUser?.id) return

    const userIsPro = await isUserPro(supabase as any, authUser.id)
    if (!userIsPro) {
      const limitReached = await reachedMessagesCommentsLimit(
        supabase as any,
        authUser.id,
        10
      )
      if (limitReached) {
        alert(handleSupabaseError({ message: "10 messages limit" }))
        return
      }
    }

    const content = shareMessage.trim() || "Shared a post"

    for (const conversationId of selectedConversations) {
      const { error } = await supabase.from("messages").insert({
        conversation_id: conversationId,
        sender_id: authUser.id,
        type: "post",
        post_id: sharePost.id,
        content,
      })

      if (error) {
        console.error("Share post error:", error)
        alert(handleSupabaseError(error))
        return
      }
    }

    setSharePost(null)
    setShareMessage("")
    setSelectedConversations([])
  }

  const modalPid = selectedPost ? String(selectedPost.id) : null
  const modalComments = modalPid
    ? commentsByPost[modalPid] ?? []
    : []
  const modalPublicDesc = selectedPost
    ? postPublicDescription(selectedPost)
    : null
  const modalTradeJoin = selectedPost ? postTradeJoin(selectedPost) : null
  const modalTicker =
    modalTradeJoin?.ticker != null ? String(modalTradeJoin.ticker) : "—"
  const modalDir =
    modalTradeJoin?.direction != null ? String(modalTradeJoin.direction) : "—"
  const modalAcctNorm = String(modalTradeJoin?.account_type ?? "")
    .trim()
    .toLowerCase()
  const modalPnl = selectedPost ? Number(selectedPost.pnl) : NaN
  const modalPnlPositive = !Number.isNaN(modalPnl) && modalPnl >= 0
  const uniquePosts = Array.from(
    new Map(posts.map((p) => [p.id, p])).values()
  )

  return (
    <div className="w-full text-white">
      <Navbar />

      <div className="flex justify-center px-4 py-6 sm:py-8 pb-10">
        <div className="w-full max-w-xl space-y-6">
          <div className="flex justify-center mb-4">
            <div className="flex gap-1 sm:gap-2 bg-white/5 p-1 rounded-xl border border-white/10">
              <button
                type="button"
                onClick={() => setMode("following")}
                className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  mode === "following"
                    ? "bg-green-500 text-white shadow-sm"
                    : "text-gray-400 hover:text-gray-200"
                }`}
              >
                Following
              </button>

              <button
                type="button"
                onClick={() => setMode("global")}
                className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  mode === "global"
                    ? "bg-green-500 text-white shadow-sm"
                    : "text-gray-400 hover:text-gray-200"
                }`}
              >
                Global
              </button>
            </div>
          </div>

          {mode === "following" && user ? (
            <>
              <input
                id="storyUploadInput"
                type="file"
                accept="image/*"
                className="hidden"
                onChange={(e) => void handleStoryUpload(e)}
              />
              <div className="flex items-center gap-4 overflow-x-auto pb-3 mb-4">
                <button
                  type="button"
                  onClick={() =>
                    document.getElementById("storyUploadInput")?.click()
                  }
                  className="flex flex-col items-center shrink-0 cursor-pointer text-left"
                >
                  <div className="w-16 h-16 rounded-full bg-green-500 flex items-center justify-center text-2xl text-white font-light leading-none hover:bg-green-600 transition-colors">
                    +
                  </div>
                  <p className="text-xs mt-1 text-gray-300">Add</p>
                </button>

                {users.map((u) => (
                  <button
                    key={u.id}
                    type="button"
                    onClick={() => openStory(u.id)}
                    className="flex flex-col items-center shrink-0 cursor-pointer text-left"
                  >
                    {u.avatar_url ? (
                      <img
                        src={u.avatar_url}
                        alt=""
                        className="w-16 h-16 rounded-full object-cover border-2 border-emerald-400 ring-2 ring-emerald-400/30"
                      />
                    ) : (
                      <div
                        className="w-16 h-16 rounded-full border-2 border-emerald-400 bg-gradient-to-br from-blue-500/40 to-emerald-500/40"
                        aria-hidden
                      />
                    )}
                    <p className="text-xs mt-1 max-w-[4.5rem] truncate text-center text-gray-200">
                      {u.username?.trim() || "User"}
                    </p>
                  </button>
                ))}
              </div>
            </>
          ) : null}

          {/* POSTS */}
          {uniquePosts.map((post) => {
            const imageSrc = postImageSrc(post.image_url)
            const pnl = Number(post.pnl)
            const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
            const pid = String(post.id)
            const likeMeta = likesByPost[pid] || { count: 0, liked: false }
            const comments = commentsByPost[pid] || []
            const publicDesc = postPublicDescription(post)
            const tradeRow = postTradeJoin(post)
            const tickerLabel = tradeRow?.ticker != null ? String(tradeRow.ticker) : "—"
            const dirLabel =
              tradeRow?.direction != null ? String(tradeRow.direction) : "—"
            const accountTypeNorm = String(tradeRow?.account_type ?? "")
              .trim()
              .toLowerCase()

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

                <div className="border-t border-white/10 px-4 py-2">
                  <div className="min-w-0">
                  <PostInteractionsEngagement
                    post={post}
                    user={user}
                    comments={comments}
                    likeMeta={likeMeta}
                    commentsOpen={!!openComments[pid]}
                    commentValue={commentDraft[pid] || ""}
                    commentSubmitting={!!commentSubmitting[pid]}
                    onToggleLike={toggleLike}
                    onToggleComments={(postId) =>
                      setOpenComments((prev) => ({
                        ...prev,
                        [postId]: !prev[postId],
                      }))
                    }
                    onCommentChange={(postId, value) =>
                      setCommentDraft((d) => ({ ...d, [postId]: value }))
                    }
                    onSubmitComment={submitComment}
                    onSharePost={setSharePost}
                    stopPropagation
                  />
                  </div>
                </div>

                <div className="space-y-3 px-4 pb-3">
                  <div className="mt-2 flex items-center justify-between gap-3">
                    <div className="flex min-w-0 items-center gap-3">
                      <div
                        className={`shrink-0 text-lg font-semibold tabular-nums ${
                          pnlPositive ? "text-emerald-400" : "text-red-400"
                        }`}
                      >
                        {Number.isNaN(pnl) ? "—" : `${pnlPositive ? "+" : ""}$${pnl}`}
                      </div>

                      <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">
                        <span className="truncate">
                          {tickerLabel} • {dirLabel}
                        </span>
                        {accountTypeNorm ? (
                          <span
                            className={`px-2 py-0.5 text-xs rounded-full ${getModeStyles(accountTypeNorm)}`}
                          >
                            {accountTypeNorm}
                          </span>
                        ) : null}
                      </div>
                    </div>

                    <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">
                      {post.rr != null && post.rr !== "" ? (
                        <span className="tabular-nums">RR {post.rr}</span>
                      ) : null}
                      {post.points !== null && post.points !== undefined ? (
                        <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
                          {post.points} pts
                        </span>
                      ) : null}
                    </div>
                  </div>

                  {publicDesc ? (
                    <p className="px-1 text-sm leading-relaxed text-white">{publicDesc}</p>
                  ) : null}

                  <p className="text-xs text-white/40">
                    {formatEST(post.created_at)}
                  </p>
                </div>

                <PostInteractionsComments
                  post={post}
                  user={user}
                  comments={comments}
                  likeMeta={likeMeta}
                  commentsOpen={!!openComments[pid]}
                  commentValue={commentDraft[pid] || ""}
                  commentSubmitting={!!commentSubmitting[pid]}
                  onToggleLike={toggleLike}
                  onToggleComments={(postId) =>
                    setOpenComments((prev) => ({
                      ...prev,
                      [postId]: !prev[postId],
                    }))
                  }
                  onCommentChange={(postId, value) =>
                    setCommentDraft((d) => ({ ...d, [postId]: value }))
                  }
                  onSubmitComment={submitComment}
                  onSharePost={setSharePost}
                  stopPropagation
                  className="px-4 pb-4 mt-2"
                />
              </article>
            )
          })}

          {loading && <p className="mt-4 text-center text-gray-400">Loading...</p>}

          {hasMore && !loading && (
            <div className="mt-4 flex justify-center">
              <button
                type="button"
                onClick={() => void loadPosts()}
                className="rounded bg-green-500 px-4 py-2 text-white"
              >
                View More
              </button>
            </div>
          )}
        </div>
      </div>

      {activeStoryUser && currentStory && (
        <div
          className="fixed inset-0 z-[9999] bg-black flex items-center justify-center"
          role="dialog"
          aria-modal="true"
          aria-label="Stories"
        >
          <div
            className="relative w-[400px] h-[700px] bg-black rounded-2xl overflow-hidden flex items-center justify-center"
            style={{ margin: 0, padding: 0 }}
          >
            <button
              type="button"
              aria-label="Close stories"
              onClick={() => {
                setActiveStoryUser(null)
                setCurrentStoryIndex(0)
              }}
              className="absolute right-3 top-3 z-[10000] rounded-full bg-black/70 px-3 py-1 text-xs text-white hover:bg-black/90"
            >
              Esc
            </button>

            <div className="absolute left-3 top-3 z-[10000] text-sm text-white">
              {users.find((u) => u.id === activeStoryUser)?.username}
            </div>

            <div className="absolute top-2 left-2 right-2 flex gap-1 z-[10000]">
              {currentStories.map((s, i) => (
                <div
                  key={s.id}
                  className={`h-[3px] flex-1 rounded ${
                    i <= currentStoryIndex ? "bg-zinc-200" : "bg-zinc-500/40"
                  }`}
                />
              ))}
            </div>

            <div className="absolute inset-0 z-0 flex h-full w-full items-center justify-center bg-black">
              <img
                src={currentStory.image_url}
                alt=""
                className="max-w-full max-h-full object-contain block"
                draggable={false}
              />
            </div>

            <button
              type="button"
              aria-label="Previous story"
              onClick={prevStory}
              className="absolute left-2 top-1/2 z-[10000] -translate-y-1/2 rounded-full bg-black/40 px-3 py-1 text-3xl text-white transition hover:scale-110"
            >
              ‹
            </button>

            <button
              type="button"
              aria-label="Next story"
              onClick={nextStory}
              className="absolute right-2 top-1/2 z-[10000] -translate-y-1/2 rounded-full bg-black/40 px-3 py-1 text-3xl text-white transition hover:scale-110"
            >
              ›
            </button>
          </div>
        </div>
      )}

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

            {modalPid ? (
              <>
                <div className="mt-3 border-t border-white/10 pt-3">
                  <div className="min-w-0">
                  <PostInteractionsEngagement
                    post={selectedPost}
                    user={user}
                    comments={modalComments}
                    likeMeta={likesByPost[modalPid] || { count: 0, liked: false }}
                    commentsOpen={!!openComments[modalPid]}
                    commentValue={commentDraft[modalPid] || ""}
                    commentSubmitting={!!commentSubmitting[modalPid]}
                    onToggleLike={toggleLike}
                    onToggleComments={(postId) =>
                      setOpenComments((prev) => ({
                        ...prev,
                        [postId]: !prev[postId],
                      }))
                    }
                    onCommentChange={(postId, value) =>
                      setCommentDraft((d) => ({ ...d, [postId]: value }))
                    }
                    onSubmitComment={submitComment}
                    onSharePost={setSharePost}
                  />
                  </div>
                </div>

                <div className="mt-3 space-y-3 text-sm">
                  <div className="mt-2 flex items-center justify-between gap-3">
                    <div className="flex min-w-0 items-center gap-3">
                      <div
                        className={`shrink-0 text-lg font-semibold tabular-nums ${
                          modalPnlPositive ? "text-emerald-400" : "text-red-400"
                        }`}
                      >
                        {Number.isNaN(modalPnl)
                          ? "—"
                          : `${modalPnlPositive ? "+" : ""}$${modalPnl}`}
                      </div>

                      <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">
                        <span className="truncate">
                          {modalTicker} • {modalDir}
                        </span>
                        {modalAcctNorm ? (
                          <span
                            className={`px-2 py-0.5 text-xs rounded-full ${getModeStyles(modalAcctNorm)}`}
                          >
                            {modalAcctNorm}
                          </span>
                        ) : null}
                      </div>
                    </div>

                    <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">
                      {selectedPost.rr != null && selectedPost.rr !== "" ? (
                        <span className="tabular-nums">RR {selectedPost.rr}</span>
                      ) : null}
                      {selectedPost.points !== null && selectedPost.points !== undefined ? (
                        <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
                          {selectedPost.points} pts
                        </span>
                      ) : null}
                    </div>
                  </div>

                  {modalPublicDesc ? (
                    <p className="text-white text-sm leading-relaxed">{modalPublicDesc}</p>
                  ) : null}

                  <p className="text-xs text-white/40">
                    {formatEST(selectedPost.created_at)}
                  </p>
                </div>

                <PostInteractionsComments
                  post={selectedPost}
                  user={user}
                  comments={modalComments}
                  likeMeta={likesByPost[modalPid] || { count: 0, liked: false }}
                  commentsOpen={!!openComments[modalPid]}
                  commentValue={commentDraft[modalPid] || ""}
                  commentSubmitting={!!commentSubmitting[modalPid]}
                  onToggleLike={toggleLike}
                  onToggleComments={(postId) =>
                    setOpenComments((prev) => ({
                      ...prev,
                      [postId]: !prev[postId],
                    }))
                  }
                  onCommentChange={(postId, value) =>
                    setCommentDraft((d) => ({ ...d, [postId]: value }))
                  }
                  onSubmitComment={submitComment}
                  onSharePost={setSharePost}
                  className="mt-3"
                />
              </>
            ) : null}

          </div>
        </div>
      )}

      {sharePost ? (
        <div
          className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4"
          onClick={() => {
            setSharePost(null)
            setShareMessage("")
            setSelectedConversations([])
          }}
        >
          <div
            className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-4 text-white"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-lg font-semibold mb-3">Send Post</h2>

            <div className="mb-3">
              {postImageSrc(sharePost.image_url) ? (
                <img
                  src={postImageSrc(sharePost.image_url) || ""}
                  className="w-full h-40 object-cover rounded"
                  alt=""
                />
              ) : null}
            </div>

            <textarea
              placeholder="Add a message..."
              value={shareMessage}
              onChange={(e) => setShareMessage(e.target.value)}
              className="w-full p-2 bg-white/5 rounded mb-3"
            />

            {shareLoading ? (
              <p className="text-sm text-gray-400">Loading chats...</p>
            ) : shareConversations.length === 0 ? (
              <p className="text-sm text-gray-400">No chats found.</p>
            ) : (
              <div className="max-h-40 overflow-y-auto space-y-2">
                {shareConversations.map((conv) => (
                  <button
                    key={conv.id}
                    type="button"
                    onClick={() => toggleConversation(conv.id)}
                    className={`w-full flex items-center gap-3 p-2 rounded cursor-pointer text-left ${
                      selectedConversations.includes(conv.id)
                        ? "bg-blue-500/20"
                        : "hover:bg-white/10"
                    }`}
                  >
                    <img
                      src={conv.avatar_url || "/default-avatar.png"}
                      className="w-8 h-8 rounded-full object-cover"
                      alt=""
                    />
                    <span>{conv.name || (conv.is_group ? "Group Chat" : "Chat")}</span>
                  </button>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={() => void handleSendPost()}
              disabled={selectedConversations.length === 0}
              className="w-full mt-3 bg-blue-600 hover:bg-blue-700 p-2 rounded disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Send
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
