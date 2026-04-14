"use client"

import Navbar from "../../components/Navbar"
import { useEffect, useMemo, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { useParams, useRouter } from "next/navigation"
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  CartesianGrid,
} from "recharts"
import TradeSocialLayer from "../../components/TradeSocialLayer"
import InputTradeForm from "../../components/InputTradeForm"
import Calendar from "../../components/Calendar"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function profileWallImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/profile_posts/${raw}`
}

function getExperience(startDate: string | null | undefined) {
  if (!startDate) return ""

  const start = new Date(startDate)
  if (Number.isNaN(start.getTime())) return ""

  const now = new Date()

  const months =
    (now.getFullYear() - start.getFullYear()) * 12 +
    (now.getMonth() - start.getMonth())

  const years = Math.floor(months / 12)
  const remainingMonths = months % 12

  return `${years}y ${remainingMonths}m`
}

function formatMoney(v: number) {
  return v < 0
    ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
    : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
}

function TradeCard({
  trade,
  profile,
  canManageTrade,
  menuOpen,
  onMenuToggle,
  onStartEditTrade,
  onTogglePinTrade,
  onSaveTrade,
  onDeleteTrade,
  showInteractions,
}: {
  trade: any
  profile: any
  canManageTrade?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onStartEditTrade?: () => void
  onTogglePinTrade?: () => void
  onSaveTrade?: () => void
  onDeleteTrade?: () => void
  showInteractions?: boolean
}) {
  const imageSrc = postImageSrc(trade.image_url)
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const direction = trade.direction ?? "—"
  const ticker = trade.ticker ?? "—"
  const rr =
    trade.rr != null && trade.rr !== "" ? trade.rr : "—"
  const desc = trade.public_description
    ? String(trade.public_description).trim()
    : ""

  return (
    <article className="mx-auto mb-6 max-w-xl overflow-hidden rounded-xl border border-white/10 bg-[#020617]">
      <div className="flex items-center justify-between px-4 py-3">
        <div className="flex min-w-0 items-center gap-3">
          <img
            src={profile.avatar_url || "/default-avatar.png"}
            alt=""
            className="h-8 w-8 shrink-0 rounded-full object-cover"
            onError={(e) => {
              e.currentTarget.src = "/default-avatar.png"
            }}
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-white">
              {profile.username || "User"}
            </p>
            <p className="text-xs font-medium text-amber-400/90">
              Trade {trade.is_pinned ? <span className="ml-2 text-yellow-400">📌</span> : null}
            </p>
          </div>
        </div>
        {canManageTrade ? (
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
                    onStartEditTrade?.()
                  }}
                  className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                >
                  Edit Trade
                </button>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation()
                    onTogglePinTrade?.()
                  }}
                  className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                >
                  {trade.is_pinned ? "Unpin Trade" : "Pin Trade"}
                </button>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation()
                    onSaveTrade?.()
                  }}
                  className="block w-full px-4 py-2 text-left text-sm hover:bg-white/10"
                >
                  Save Trade
                </button>
                <button
                  type="button"
                  onClick={(e) => {
                    e.stopPropagation()
                    onDeleteTrade?.()
                  }}
                  className="block w-full px-4 py-2 text-left text-sm text-red-400 hover:bg-white/10"
                >
                  Delete Trade
                </button>
              </div>
            ) : null}
          </div>
        ) : null}
      </div>

      {imageSrc ? (
        <div className="relative w-full bg-black/40">
          <img
            src={imageSrc}
            alt=""
            className="max-h-[400px] w-full object-cover"
          />
        </div>
      ) : (
        <div className="flex min-h-[80px] items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] text-xs text-gray-500">
          No screenshot
        </div>
      )}

      {showInteractions ? (
        <div className="border-t border-white/10 px-4 py-3">
          <TradeSocialLayer
            tradeId={trade.id}
            currentUserId={trade.currentUserId}
            tradeOwnerUserId={trade.user_id}
          />
        </div>
      ) : null}

      <div className="space-y-1 px-4 py-3">
        <p className="text-sm text-gray-100">
          <span className="font-medium text-white">{ticker}</span>
          {" · "}
          <span>{direction}</span>
          {" · "}
          <span
            className={
              Number.isFinite(pnl)
                ? pnl >= 0
                  ? "text-emerald-400"
                  : "text-red-400"
                : "text-gray-400"
            }
          >
            {Number.isFinite(pnl) ? formatMoney(pnl) : "—"}
          </span>
          {" · RR "}
          {rr}
        </p>
        {desc ? (
          <p className="text-sm leading-relaxed text-gray-300">{desc}</p>
        ) : null}
        <p className="text-xs text-gray-500">
          {new Date(trade.created_at).toLocaleString()}
        </p>
      </div>
    </article>
  )
}

function PostCard({
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
  onToggleComments,
  commentsOpen,
  likeMeta,
  comments,
  commentText,
  onCommentChange,
  onCommentSubmit,
  commentSubmitting,
}: {
  post: any
  profile: any
  canManagePost?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onStartEditPost?: () => void
  onTogglePinPost?: () => void
  onSavePost?: () => void
  onDeletePost?: () => void
  showInteractions?: boolean
  onLike?: () => void
  onToggleComments?: () => void
  commentsOpen?: boolean
  likeMeta?: { count: number; liked: boolean }
  comments?: any[]
  commentText?: string
  onCommentChange?: (value: string) => void
  onCommentSubmit?: () => void
  commentSubmitting?: boolean
}) {
  const imgSrc = profileWallImageSrc(post.image_url)

  return (
    <div className="mx-auto max-w-xl rounded-xl border border-white/10 bg-[#020617] p-4">
      <div className="mb-3 flex items-center justify-between gap-3">
        <div className="flex min-w-0 items-center gap-3">
          <img
            src={profile.avatar_url || "/default-avatar.png"}
            alt=""
            className="h-8 w-8 rounded-full object-cover"
            onError={(e) => {
              e.currentTarget.src = "/default-avatar.png"
            }}
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-medium text-white">
              {profile.username || "User"}
            </p>
            <p className="text-xs font-medium text-sky-400/90">
              Post {post.is_pinned ? <span className="ml-2 text-yellow-400">📌</span> : null}
            </p>
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

      {post.content ? (
        <p className="mb-3 text-sm leading-relaxed text-gray-200">
          {post.content}
        </p>
      ) : null}

      {imgSrc ? (
        <img
          src={imgSrc}
          alt=""
          className="max-h-[420px] w-full rounded-lg object-cover"
          onError={(e) => {
            e.currentTarget.style.display = "none"
          }}
        />
      ) : null}

      <p className="mt-2 text-xs text-gray-500">
        {new Date(post.created_at).toLocaleString()}
      </p>
      {showInteractions ? (
        <div className="mt-3 border-t border-white/10 pt-3">
          <div className="flex items-center gap-4 px-1 text-sm">
            <button
              type="button"
              onClick={onLike}
              className="flex items-center gap-1 text-gray-300 hover:text-white"
            >
              <span>{likeMeta?.liked ? "❤️" : "🤍"}</span>
              <span className="tabular-nums">{likeMeta?.count ?? 0}</span>
            </button>
            <button
              type="button"
              onClick={onToggleComments}
              className="text-gray-300 hover:text-white"
            >
              💬 {comments?.length ?? 0}
            </button>
          </div>
          <p className="px-1 pt-2 text-sm font-medium text-white">
            {(likeMeta?.count ?? 0).toLocaleString()} likes
          </p>
          {commentsOpen ? (
            <div className="mt-3 space-y-3">
              <div className="max-h-36 space-y-1 overflow-y-auto text-sm text-gray-300">
                {(comments || []).map((c: any) => (
                  <p key={c.id}>
                    <span className="font-medium text-white">
                      {c.profiles?.username || "User"}
                    </span>{" "}
                    {c.content}
                  </p>
                ))}
              </div>
              <div className="flex gap-2">
                <input
                  value={commentText || ""}
                  onChange={(e) => onCommentChange?.(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && !e.shiftKey) {
                      e.preventDefault()
                      onCommentSubmit?.()
                    }
                  }}
                  placeholder="Add a comment..."
                  className="flex-1 rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white placeholder:text-gray-500"
                />
                <button
                  type="button"
                  onClick={onCommentSubmit}
                  disabled={commentSubmitting || !(commentText || "").trim()}
                  className="rounded-lg bg-blue-500 px-3 py-2 text-sm text-white disabled:opacity-40"
                >
                  Post
                </button>
              </div>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

export default function ProfilePage() {
  const PAGE_SIZE = 5

  const params = useParams()
  const router = useRouter()
  const rawId = params.id
  const profileId =
    typeof rawId === "string" ? rawId : Array.isArray(rawId) ? rawId[0] : undefined

  const [profile, setProfile] = useState<any>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [allTrades, setAllTrades] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [hasMore, setHasMore] = useState(true)
  const [loading, setLoading] = useState(true)
  const [followersCount, setFollowersCount] = useState(0)
  const [followingCount, setFollowingCount] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [isFollowing, setIsFollowing] = useState(false)
  const [followBusy, setFollowBusy] = useState(false)
  const [messageBusy, setMessageBusy] = useState(false)
  const [showFollowers, setShowFollowers] = useState(false)
  const [showFollowing, setShowFollowing] = useState(false)
  const [followersModalUsers, setFollowersModalUsers] = useState<any[]>([])
  const [followingModalUsers, setFollowingModalUsers] = useState<any[]>([])
  const [wallPosts, setWallPosts] = useState<any[]>([])
  const [activeTab, setActiveTab] = useState<
    "trades" | "posts" | "calendar" | "stats"
  >(
    "trades"
  )
  const [showCreatePost, setShowCreatePost] = useState(false)
  const [showStoryModal, setShowStoryModal] = useState(false)
  const [postContent, setPostContent] = useState("")
  const [postImage, setPostImage] = useState<File | null>(null)
  const [creatingPost, setCreatingPost] = useState(false)
  const [openCommentsState, setOpenComments] = useState<
    Record<string, boolean>
  >({})
  const [likesByPost, setLikesByPost] = useState<
    Record<string, { count: number; liked: boolean }>
  >({})
  const [commentsByPost, setCommentsByPost] = useState<Record<string, any[]>>({})
  const [commentDraft, setCommentDraft] = useState<Record<string, string>>({})
  const [commentSubmitting, setCommentSubmitting] = useState<
    Record<string, boolean>
  >({})
  const [openMenuId, setOpenMenuId] = useState<string | null>(null)
  const [openTradeMenuId, setOpenTradeMenuId] = useState<string | null>(null)
  const [editingPost, setEditingPost] = useState<any | null>(null)
  const [editContent, setEditContent] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [calendarTrades, setCalendarTrades] = useState<any[]>([])
  const [accountFilter, setAccountFilter] = useState("All")
  const [accountTypeFilter, setAccountTypeFilter] = useState("All")

  const fetchTrades = async (forProfileId: string, reset = false) => {
    const from = reset ? 0 : page * PAGE_SIZE
    const to = from + PAGE_SIZE - 1

    const { data, error } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", forProfileId)
      .order("created_at", { ascending: false })
      .range(from, to)

    if (error) {
      console.error("Trade fetch error FULL:", JSON.stringify(error, null, 2))
      return
    }

    if (reset) {
      setTrades(data || [])
      setPage(1)
      setHasMore((data || []).length >= PAGE_SIZE)
      return
    }

    setTrades((prev) => [...prev, ...(data || [])])
    setPage((prev) => prev + 1)
    if (!data || data.length < PAGE_SIZE) {
      setHasMore(false)
    }
  }

  useEffect(() => {
    if (!profileId) {
      setProfile(null)
      setTrades([])
      setPage(0)
      setHasMore(true)
      setLoading(false)
      return
    }

    console.log("ProfileId from URL:", profileId)

    setProfile(null)
    setTrades([])
    setPage(0)
    setHasMore(true)
    setWallPosts([])
    setLoading(true)

    fetchProfile(profileId)
  }, [profileId])

  useEffect(() => {
    console.log("Trades:", trades)
  }, [trades])

  useEffect(() => {
    if (!profile?.id) {
      setWallPosts([])
      return
    }

    let cancelled = false

    async function fetchWallPosts() {
      const { data, error } = await supabase
        .from("profile_posts")
        .select("*")
        .eq("user_id", profile.id)
        .order("created_at", { ascending: false })

      if (cancelled) return
      if (error) {
        console.error("profile_posts fetch:", error)
        setWallPosts([])
        return
      }
      setWallPosts(data || [])
    }

    void fetchWallPosts()

    return () => {
      cancelled = true
    }
  }, [profile?.id])

  useEffect(() => {
    if (!profile?.id) {
      setAllTrades([])
      return
    }

    let cancelled = false
    async function fetchAllTrades() {
      const { data, error } = await supabase
        .from("trades")
        .select("*")
        .eq("user_id", profile.id)

      if (cancelled) return
      if (error) {
        console.error("all trades fetch:", error)
        setAllTrades([])
        return
      }
      setAllTrades(data || [])
    }

    void fetchAllTrades()
    return () => {
      cancelled = true
    }
  }, [profile?.id])

  useEffect(() => {
    if (!profile?.id) {
      setCalendarTrades([])
      return
    }

    let cancelled = false
    async function fetchCalendarTrades() {
      const { data, error } = await supabase
        .from("trades")
        .select("id, created_at, pnl, ticker, direction")
        .eq("user_id", profile.id)

      if (cancelled) return
      if (error) {
        console.error("calendar trades fetch:", error)
        setCalendarTrades([])
        return
      }

      setCalendarTrades(data || [])
    }

    void fetchCalendarTrades()
    return () => {
      cancelled = true
    }
  }, [profile?.id])

  useEffect(() => {
    if (showCreatePost || editingPost) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
    document.body.style.overflow = ""
    return undefined
  }, [showCreatePost, editingPost])

  useEffect(() => {
    if (!showCreatePost && !editingPost) return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setShowCreatePost(false)
        setEditingPost(null)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [showCreatePost, editingPost])

  async function fetchProfile(forProfileId: string) {
    const { data: sessionData } = await supabase.auth.getSession()
    const uid = sessionData?.session?.user?.id ?? null
    setCurrentUserId(uid)

    const { data: prof, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", forProfileId)
      .single()

    if (!prof || error) {
      setProfile(null)
      setTrades([])
      setPage(0)
      setHasMore(false)
      setFollowersCount(0)
      setFollowingCount(0)
      setIsFollowing(false)
      setLoading(false)
      return
    }

    let following = false
    if (uid && uid !== prof.id) {
      const { data: followRow } = await supabase
        .from("followers")
        .select("*")
        .eq("follower_id", uid)
        .eq("following_id", prof.id)
        .maybeSingle()

      following = !!followRow
    }

    setProfile(prof)
    setIsFollowing(following)

    const { count: followersN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("following_id", prof.id)

    const { count: followingN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("follower_id", prof.id)

    setFollowersCount(followersN ?? 0)
    setFollowingCount(followingN ?? 0)

    const isPrivateProfile = prof.is_private === true
    const canLoadTrades =
      !isPrivateProfile || uid === forProfileId || following

    if (canLoadTrades) {
      await fetchTrades(forProfileId, true)
    } else {
      setTrades([])
      setPage(0)
      setHasMore(false)
    }

    setLoading(false)
  }

  async function handleFollowToggle() {
    if (!currentUserId || !profile || currentUserId === profile.id || followBusy)
      return

    setFollowBusy(true)

    if (isFollowing) {
      await supabase
        .from("followers")
        .delete()
        .eq("follower_id", currentUserId)
        .eq("following_id", profile.id)

      setIsFollowing(false)
      if (profile.is_private === true) {
        setTrades([])
        setPage(0)
        setHasMore(false)
      }
    } else {
      await supabase.from("followers").insert({
        follower_id: currentUserId,
        following_id: profile.id,
      })

      setIsFollowing(true)
      if (profile.is_private === true && profileId) {
        setPage(0)
        setHasMore(true)
        await fetchTrades(profileId, true)
      }
    }

    const { count: followersN } = await supabase
      .from("followers")
      .select("*", { count: "exact", head: true })
      .eq("following_id", profile.id)

    setFollowersCount(followersN ?? 0)

    setFollowBusy(false)
  }

  async function findExistingDmConversationId(
    me: string,
    them: string
  ): Promise<string | null> {
    const { data: mine } = await supabase
      .from("conversation_participants")
      .select("conversation_id")
      .eq("user_id", me)

    const ids = [...new Set(mine?.map((r) => r.conversation_id) ?? [])]
    if (ids.length === 0) return null

    const { data: rows } = await supabase
      .from("conversation_participants")
      .select("conversation_id, user_id")
      .in("conversation_id", ids)

    const byConvo = new Map<string, Set<string>>()
    for (const row of rows ?? []) {
      if (!byConvo.has(row.conversation_id)) {
        byConvo.set(row.conversation_id, new Set())
      }
      byConvo.get(row.conversation_id)!.add(row.user_id)
    }

    for (const [cid, users] of byConvo) {
      if (users.size === 2 && users.has(me) && users.has(them)) return cid
    }

    return null
  }

  async function handleMessage() {
    if (!currentUserId || !profile || currentUserId === profile.id) return

    setMessageBusy(true)
    try {
      const existingId = await findExistingDmConversationId(
        currentUserId,
        profile.id
      )

      if (existingId) {
        router.push(`/messages/${existingId}`)
        return
      }

      const { data: convo, error: convErr } = await supabase
        .from("conversations")
        .insert({})
        .select("id")
        .single()

      if (convErr || !convo?.id) {
        console.error(convErr)
        return
      }

      const { error: partErr } = await supabase
        .from("conversation_participants")
        .insert([
          { conversation_id: convo.id, user_id: currentUserId },
          { conversation_id: convo.id, user_id: profile.id },
        ])

      if (partErr) {
        console.error(partErr)
        return
      }

      router.push(`/messages/${convo.id}`)
    } finally {
      setMessageBusy(false)
    }
  }

  function closeFollowModals() {
    setShowFollowers(false)
    setShowFollowing(false)
  }

  async function openFollowersModal() {
    if (!profile) return
    setShowFollowing(false)
    setShowFollowers(true)

    const { data: rows } = await supabase
      .from("followers")
      .select("follower_id")
      .eq("following_id", profile.id)

    const ids = [...new Set(rows?.map((r) => r.follower_id).filter(Boolean) ?? [])]
    if (ids.length === 0) {
      setFollowersModalUsers([])
      return
    }

    const { data: profs } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, name")
      .in("id", ids)

    setFollowersModalUsers(profs ?? [])
  }

  async function openFollowingModal() {
    if (!profile) return
    setShowFollowers(false)
    setShowFollowing(true)

    const { data: rows } = await supabase
      .from("followers")
      .select("following_id")
      .eq("follower_id", profile.id)

    const ids = [...new Set(rows?.map((r) => r.following_id).filter(Boolean) ?? [])]
    if (ids.length === 0) {
      setFollowingModalUsers([])
      return
    }

    const { data: profs } = await supabase
      .from("profiles")
      .select("id, username, avatar_url, name")
      .in("id", ids)

    setFollowingModalUsers(profs ?? [])
  }

  async function handleCreatePost() {
    if (!currentUserId || !profile || currentUserId !== profile.id) return

    const text = postContent.trim()
    if (!text && !postImage) {
      alert("Add some text or an image.")
      return
    }

    setCreatingPost(true)
    let imageUrl: string | null = null

    if (postImage) {
      const fileExt = postImage.name.split(".").pop() || "jpg"
      const fileName = `${currentUserId}/${Date.now()}.${fileExt}`

      const { error: upErr } = await supabase.storage
        .from("profile_posts")
        .upload(fileName, postImage, { upsert: true })

      if (upErr) {
        console.error(upErr)
        alert(upErr.message)
        setCreatingPost(false)
        return
      }

      const base = process.env.NEXT_PUBLIC_SUPABASE_URL
      imageUrl = base
        ? `${base}/storage/v1/object/public/profile_posts/${fileName}`
        : null
    }

    const { error } = await supabase.from("profile_posts").insert({
      user_id: currentUserId,
      content: text || null,
      image_url: imageUrl,
    })

    setCreatingPost(false)

    if (error) {
      console.error(error)
      alert(error.message)
      return
    }

    setShowCreatePost(false)
    setPostContent("")
    setPostImage(null)

    const { data } = await supabase
      .from("profile_posts")
      .select("*")
      .eq("user_id", profile.id)
      .order("created_at", { ascending: false })

    setWallPosts(data || [])
  }

  const posts = wallPosts
  const sortedPosts = [...posts].sort((a, b) => {
    if (a.is_pinned && !b.is_pinned) return -1
    if (!a.is_pinned && b.is_pinned) return 1
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  async function loadPostEngagement(postList: any[]) {
    if (!postList.length) {
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

    const likesMap: Record<string, { count: number; liked: boolean }> = {}
    for (const id of ids) {
      likesMap[String(id)] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const key = String(row.post_id)
      if (!likesMap[key]) likesMap[key] = { count: 0, liked: false }
      likesMap[key].count += 1
      if (currentUserId && row.user_id === currentUserId) likesMap[key].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) commentsMap[String(id)] = []
    for (const row of commentsRows || []) {
      const key = String(row.post_id)
      if (!commentsMap[key]) commentsMap[key] = []
      commentsMap[key].push(row)
    }

    setLikesByPost(likesMap)
    setCommentsByPost(commentsMap)
  }

  useEffect(() => {
    void loadPostEngagement(posts)
  }, [currentUserId, posts.length])

  useEffect(() => {
    const handleClick = () => {
      setOpenMenuId(null)
      setOpenTradeMenuId(null)
    }
    window.addEventListener("click", handleClick)
    return () => window.removeEventListener("click", handleClick)
  }, [])

  async function handleLike(id: string, type: "post" | "trade") {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    const meta = likesByPost[key] || { count: 0, liked: false }
    if (meta.liked) {
      const { error } = await supabase
        .from("likes")
        .delete()
        .eq("post_id", key)
        .eq("user_id", currentUserId)
      if (error) return console.error(error)
      setLikesByPost((prev) => ({
        ...prev,
        [key]: { count: Math.max(0, meta.count - 1), liked: false },
      }))
      return
    }
    const { error } = await supabase
      .from("likes")
      .insert({ post_id: key, user_id: currentUserId })
    if (error) return console.error(error)
    setLikesByPost((prev) => ({
      ...prev,
      [key]: { count: meta.count + 1, liked: true },
    }))
  }

  const openComments = (id: string, type: "post" | "trade") => {
    const key = `${type}:${id}`
    setOpenComments((prev) => ({
      ...prev,
      [key]: !prev[key],
    }))
  }

  async function submitComment(id: string, type: "post" | "trade") {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    const text = (commentDraft[key] || "").trim()
    if (!text) return
    setCommentSubmitting((s) => ({ ...s, [key]: true }))
    const { data, error } = await supabase
      .from("comments")
      .insert({
        post_id: key,
        user_id: currentUserId,
        content: text,
      })
      .select("*, profiles(username)")
      .single()
    setCommentSubmitting((s) => ({ ...s, [key]: false }))
    if (error) return console.error(error)
    setCommentsByPost((prev) => ({ ...prev, [key]: [...(prev[key] || []), data] }))
    setCommentDraft((prev) => ({ ...prev, [key]: "" }))
  }

  async function handleDeletePost(postId: string) {
    const confirmDelete = window.confirm("Delete this post?")
    if (!confirmDelete) return

    const { error } = await supabase
      .from("profile_posts")
      .delete()
      .eq("id", postId)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) => prev.filter((p) => String(p.id) !== String(postId)))
    setOpenMenuId(null)
  }

  async function handleUpdatePost() {
    if (!editingPost) return
    const { error } = await supabase
      .from("profile_posts")
      .update({ content: editContent })
      .eq("id", editingPost.id)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) =>
      prev.map((p) =>
        String(p.id) === String(editingPost.id) ? { ...p, content: editContent } : p
      )
    )
    setEditingPost(null)
  }

  async function handlePinPost(post: any) {
    const { error } = await supabase
      .from("profile_posts")
      .update({ is_pinned: !post.is_pinned })
      .eq("id", post.id)

    if (error) {
      console.error(error)
      return
    }

    setWallPosts((prev) =>
      prev.map((p) =>
        String(p.id) === String(post.id) ? { ...p, is_pinned: !p.is_pinned } : p
      )
    )
    setOpenMenuId(null)
  }

  async function handleSavePost(postId: string) {
    if (!currentUserId) return
    const { error } = await supabase.from("saved_posts").insert({
      user_id: currentUserId,
      post_id: postId,
    })
    if (error) console.error(error)
    setOpenMenuId(null)
  }

  function openEditTradeModal(trade: any) {
    setEditingTrade({ ...trade })
  }

  async function handlePinTrade(trade: any) {
    const { error } = await supabase
      .from("trades")
      .update({ is_pinned: !trade.is_pinned })
      .eq("id", trade.id)

    if (error) {
      console.error(error)
      return
    }

    setTrades((prev) =>
      prev.map((t) =>
        String(t.id) === String(trade.id) ? { ...t, is_pinned: !t.is_pinned } : t
      )
    )
    setOpenTradeMenuId(null)
  }

  async function handleSaveTrade(tradeId: string) {
    if (!currentUserId) return
    const { error } = await supabase.from("saved_trades").insert({
      user_id: currentUserId,
      trade_id: tradeId,
    })
    if (error) console.error(error)
    setOpenTradeMenuId(null)
  }

  async function handleDeleteTrade(tradeId: string) {
    const confirmDelete = window.confirm("Delete this trade?")
    if (!confirmDelete) return
    const { error } = await supabase.from("trades").delete().eq("id", tradeId)
    if (error) {
      console.error(error)
      return
    }
    setTrades((prev) => prev.filter((t) => String(t.id) !== String(tradeId)))
    setOpenTradeMenuId(null)
  }

  const canViewTrades =
    !!profile &&
    (profile.is_private !== true ||
      currentUserId === profile.id ||
      isFollowing)

  const sortedTrades = [...trades].sort((a, b) => {
    if (a.is_pinned && !b.is_pinned) return -1
    if (!a.is_pinned && b.is_pinned) return 1
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  const accountOptions = useMemo(() => {
    const ids = new Set<string>()
    for (const t of allTrades) {
      if (t.account_id != null && String(t.account_id).trim() !== "") {
        ids.add(String(t.account_id))
      }
    }
    return ["All", ...Array.from(ids)]
  }, [allTrades])

  useEffect(() => {
    console.log(allTrades)
  }, [allTrades])

  const filteredTrades = allTrades.filter((trade) => {
    const matchesAccount =
      accountFilter === "All"
        ? true
        : String(trade.account_id || "") === String(accountFilter)

    const type = String(trade.account_type || "").toLowerCase()
    const matchesType =
      accountTypeFilter === "All"
        ? true
        : type.includes(accountTypeFilter.toLowerCase())

    return matchesAccount && matchesType
  })

  const statsVisible = canViewTrades

  const totalTrades = canViewTrades ? filteredTrades.length : 0
  const wins = canViewTrades ? filteredTrades.filter((t) => t.pnl > 0).length : 0
  const totalPnL = canViewTrades
    ? filteredTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)
    : 0
  const winRate =
    canViewTrades && totalTrades ? (wins / totalTrades) * 100 : 0
  const avgRR =
    canViewTrades && totalTrades
      ? filteredTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
        totalTrades
      : 0

  const biggestWin = filteredTrades.length
    ? Math.max(...filteredTrades.map((t) => t.pnl || 0))
    : 0

  const biggestLoss = filteredTrades.length
    ? Math.min(...filteredTrades.map((t) => t.pnl || 0))
    : 0

  const longTrades = filteredTrades.filter((t) => t.direction === "Long").length
  const shortTrades = filteredTrades.filter((t) => t.direction === "Short").length

  const equityData = filteredTrades
    .slice()
    .reverse()
    .reduce(
      (acc: { index: number; equity: number }[], trade, i) => {
        const prev = acc[i - 1]?.equity || 0
        acc.push({
          index: i,
          equity: prev + (trade.pnl || 0),
        })
        return acc
      },
      [] as { index: number; equity: number }[]
    )

  const currentEquity =
    equityData.length > 0 ? equityData[equityData.length - 1].equity : 0

  function formatCurrency(value: number) {
    return `${value < 0 ? "-" : ""}$${Math.abs(value).toLocaleString()}`
  }

  if (!profileId) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-red-400">
          Invalid profile
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-400">
          Loading profile...
        </div>
      </>
    )
  }

  if (!profile) {
    return (
      <>
        <Navbar />
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-red-400">
          User not found
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100">
        <div className="mx-auto max-w-5xl space-y-4 px-4 py-6 sm:px-6 lg:px-8">
          <div className="bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md">
            <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
              <div className="flex min-w-0 flex-1 flex-col items-center gap-6 sm:flex-row sm:items-center sm:gap-6">
                <img
                  src={profile.avatar_url || "/default-avatar.png"}
                  alt=""
                  onError={(e) => {
                    e.currentTarget.src = "/default-avatar.png"
                  }}
                  className="h-20 w-20 shrink-0 rounded-full border border-white/10 object-cover"
                />

                <div className="min-w-0 flex-1 text-center sm:text-left">
                  <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start sm:gap-3">
                    <h2 className="text-xl font-semibold text-white">
                      {profile.username || "User"}
                    </h2>

                    {currentUserId === profile.id && (
                      <button
                        type="button"
                        onClick={() => router.push("/settings")}
                        className="rounded-md bg-white/10 px-3 py-1 text-sm text-gray-100 hover:bg-white/20"
                      >
                        Settings
                      </button>
                    )}

                    {currentUserId && currentUserId !== profile.id && (
                      <>
                        <button
                          type="button"
                          onClick={handleFollowToggle}
                          disabled={followBusy}
                          className={`rounded-md px-3 py-1 text-sm font-medium text-white disabled:opacity-50 ${
                            isFollowing
                              ? "bg-red-500 hover:bg-red-600"
                              : "bg-blue-500 hover:bg-blue-600"
                          }`}
                        >
                          {isFollowing ? "Unfollow" : "Follow"}
                        </button>

                        <button
                          type="button"
                          onClick={handleMessage}
                          disabled={messageBusy}
                          className="rounded-md border border-white/10 bg-white/10 px-3 py-1 text-sm text-gray-100 hover:bg-white/20 disabled:opacity-50"
                        >
                          Message
                        </button>
                      </>
                    )}
                  </div>

                  {profile.name && profile.name !== profile.username ? (
                    <p className="mt-1 text-sm text-gray-400">{profile.name}</p>
                  ) : null}

                  <p className="mt-1 text-sm text-gray-400">
                    {profile.trading_style ||
                      profile.trading_model ||
                      "—"}{" "}
                    • {getExperience(profile.started_trading) || "N/A"}
                  </p>

                  <div className="mt-2 flex flex-wrap items-center justify-center gap-4 text-sm text-gray-400 sm:justify-start">
                    <span
                      role="button"
                      tabIndex={0}
                      onClick={openFollowersModal}
                      onKeyDown={(e) =>
                        e.key === "Enter" && openFollowersModal()
                      }
                      className="cursor-pointer tabular-nums hover:text-white"
                    >
                      <span className="font-semibold text-gray-200">
                        {followersCount}
                      </span>{" "}
                      Followers
                    </span>
                    <span
                      role="button"
                      tabIndex={0}
                      onClick={openFollowingModal}
                      onKeyDown={(e) =>
                        e.key === "Enter" && openFollowingModal()
                      }
                      className="cursor-pointer tabular-nums hover:text-white"
                    >
                      <span className="font-semibold text-gray-200">
                        {followingCount}
                      </span>{" "}
                      Following
                    </span>
                  </div>

                  <p className="mt-2 text-sm leading-relaxed text-gray-300">
                    {profile.bio || "No bio yet"}
                  </p>
                </div>
              </div>

              {currentUserId === profile.id && (
                <div className="flex shrink-0 justify-center gap-2 sm:justify-end sm:pt-1">
                  <button
                    type="button"
                    onClick={() => setShowStoryModal(true)}
                    className="rounded-md bg-blue-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-600"
                  >
                    + Story
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowCreatePost(true)}
                    className="rounded-md bg-blue-500 px-3 py-1.5 text-xs font-medium text-white hover:bg-blue-600"
                  >
                    + Post
                  </button>
                </div>
              )}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 md:grid-cols-4 md:gap-4">
            <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-center">
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? totalTrades : "—"}
              </p>
              <p className="text-xs text-gray-400">Trades</p>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-center">
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? `${winRate.toFixed(0)}%` : "—"}
              </p>
              <p className="text-xs text-gray-400">Win %</p>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-center">
              <p
                className={`text-lg font-semibold tabular-nums ${
                  !statsVisible
                    ? "text-white"
                    : totalPnL >= 0
                    ? "text-emerald-400"
                    : "text-red-400"
                }`}
              >
                {statsVisible ? formatMoney(totalPnL) : "—"}
              </p>
              <p className="text-xs text-gray-400">P&amp;L</p>
            </div>

            <div className="rounded-lg border border-white/10 bg-white/5 p-3 text-center">
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? avgRR.toFixed(2) : "—"}
              </p>
              <p className="text-xs text-gray-400">Avg RR</p>
            </div>
          </div>

          {!statsVisible && profile.is_private === true ? (
            <p className="text-center text-xs text-gray-500">
              Follow to unlock trading stats in this row.
            </p>
          ) : null}

          <div className="mt-6 flex gap-6 border-b border-white/10 pb-2">
            <button
              type="button"
              className={`text-sm ${
                activeTab === "trades"
                  ? "text-white border-b-2 border-blue-500 pb-1"
                  : "text-gray-400"
              }`}
              onClick={() => setActiveTab("trades")}
            >
              Trades
            </button>

            <button
              type="button"
              className={`text-sm ${
                activeTab === "posts"
                  ? "text-white border-b-2 border-blue-500 pb-1"
                  : "text-gray-400"
              }`}
              onClick={() => setActiveTab("posts")}
            >
              Posts
            </button>

            <button
              type="button"
              className={`text-sm ${
                activeTab === "stats"
                  ? "text-white border-b-2 border-blue-500 pb-1"
                  : "text-gray-400"
              }`}
              onClick={() => setActiveTab("stats")}
            >
              Stats
            </button>

            <button
              type="button"
              className={`text-sm ${
                activeTab === "calendar"
                  ? "text-white border-b-2 border-blue-500 pb-1"
                  : "text-gray-400"
              }`}
              onClick={() => setActiveTab("calendar")}
            >
              Calendar
            </button>
          </div>

          <div className="mt-4 space-y-6">
            {activeTab === "trades" && (
              <div className="mx-auto mt-4 w-full max-w-xl space-y-6 pb-8">
                {sortedTrades.length === 0 ? (
                  <p className="text-center text-sm text-gray-400">
                    {currentUserId === profile.id
                      ? "No trades yet."
                      : "No trades yet."}
                  </p>
                ) : (
                  sortedTrades.map((trade) => (
                    <TradeCard
                      key={trade.id}
                      trade={{ ...trade, currentUserId }}
                      profile={profile}
                      canManageTrade={currentUserId === profile.id}
                      menuOpen={openTradeMenuId === String(trade.id)}
                      onMenuToggle={() =>
                        setOpenTradeMenuId((prev) =>
                          prev === String(trade.id) ? null : String(trade.id)
                        )
                      }
                      onStartEditTrade={() => {
                        openEditTradeModal(trade)
                        setOpenTradeMenuId(null)
                      }}
                      onTogglePinTrade={() => void handlePinTrade(trade)}
                      onSaveTrade={() => void handleSaveTrade(String(trade.id))}
                      onDeleteTrade={() => void handleDeleteTrade(String(trade.id))}
                      showInteractions={true}
                    />
                  ))
                )}
                {hasMore && canViewTrades ? (
                  <button
                    type="button"
                    onClick={() => {
                      if (profile?.id) void fetchTrades(profile.id)
                    }}
                    className="mt-4 w-full rounded bg-white/10 py-2 hover:bg-white/20"
                  >
                    Load More
                  </button>
                ) : null}
              </div>
            )}

            {activeTab === "posts" && (
              <div className="mx-auto mt-4 w-full max-w-xl space-y-6 pb-8">
                <button
                  type="button"
                  onClick={() => setShowCreatePost(true)}
                  className="w-full rounded bg-blue-500 px-4 py-2 text-sm font-medium hover:bg-blue-600"
                >
                  + Create Post
                </button>

                {sortedPosts.length === 0 ? (
                  <p className="text-center text-sm text-gray-400">No posts yet.</p>
                ) : (
                  sortedPosts.map((post) => {
                    const key = String(post.id)
                    return (
                      <PostCard
                        key={post.id}
                        post={post}
                        profile={profile}
                        canManagePost={currentUserId === profile.id}
                        menuOpen={openMenuId === key}
                        onMenuToggle={() =>
                          setOpenMenuId((prev) => (prev === key ? null : key))
                        }
                        onStartEditPost={() => {
                          setEditingPost(post)
                          setEditContent(post.content || "")
                          setOpenMenuId(null)
                        }}
                        onTogglePinPost={() => void handlePinPost(post)}
                        onSavePost={() => void handleSavePost(key)}
                        onDeletePost={() => void handleDeletePost(key)}
                        showInteractions={true}
                        onLike={() => void handleLike(key, "post")}
                        onToggleComments={() => openComments(key, "post")}
                        commentsOpen={!!openCommentsState[`post:${key}`]}
                        likeMeta={
                          likesByPost[key] || { count: 0, liked: false }
                        }
                        comments={commentsByPost[key] || []}
                        commentText={commentDraft[key] || ""}
                        onCommentChange={(value) =>
                          setCommentDraft((prev) => ({ ...prev, [key]: value }))
                        }
                        onCommentSubmit={() => void submitComment(key, "post")}
                        commentSubmitting={!!commentSubmitting[key]}
                      />
                    )
                  })
                )}
              </div>
            )}

            {activeTab === "calendar" && (
              <div className="mt-4">
                <Calendar
                  trades={filteredTrades}
                  showAccountFilter={false}
                  showControls={false}
                />
              </div>
            )}

            {activeTab === "stats" && (
              <div className="space-y-6">
                {!canViewTrades ? (
                  <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
                    <p className="text-lg text-gray-100">Private Profile</p>
                    <p className="mt-2 text-sm text-gray-400">
                      Follow this user to see their trades and stats.
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="mb-4 flex flex-wrap items-center justify-between gap-2">
                      <div className="flex items-center gap-2">
                        <label className="text-xs text-gray-400">Account</label>
                        <select
                          value={accountFilter}
                          onChange={(e) => setAccountFilter(e.target.value)}
                          className="rounded-lg border border-white/10 bg-white/10 px-3 py-1.5 text-xs text-gray-200"
                        >
                          {accountOptions.map((acc) => (
                            <option key={acc} value={acc} className="bg-[#0f172a]">
                              {acc}
                            </option>
                          ))}
                        </select>
                      </div>

                      <div className="flex gap-1 rounded-lg bg-white/5 p-1">
                        {["All", "Eval", "Funded", "Live"].map((type) => (
                          <button
                            key={type}
                            type="button"
                            onClick={() => setAccountTypeFilter(type)}
                            className={`rounded px-3 py-1 text-xs ${
                              accountTypeFilter === type
                                ? "bg-blue-500 text-white"
                                : "text-gray-400 hover:text-white"
                            }`}
                          >
                            {type}
                          </button>
                        ))}
                      </div>
                    </div>

                    {filteredTrades.length === 0 ? (
                      <p className="text-sm text-gray-400">
                        No trades for this filter selection
                      </p>
                    ) : null}

                    <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                      <Stat title="Trades" value={totalTrades} />

                      <Stat title="Win %" value={`${winRate.toFixed(1)}%`} />

                      <Stat
                        title="Total P&L"
                        value={formatCurrency(totalPnL)}
                        positive={totalPnL >= 0}
                      />

                      <Stat title="Avg RR" value={avgRR.toFixed(2)} />
                    </div>

                    <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Biggest Win</p>
                        <p className="font-semibold text-green-400">
                          ${biggestWin.toFixed(2)}
                        </p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Biggest Loss</p>
                        <p className="font-semibold text-red-400">
                          ${biggestLoss.toFixed(2)}
                        </p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Long Trades</p>
                        <p className="font-semibold">{longTrades}</p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Short Trades</p>
                        <p className="font-semibold">{shortTrades}</p>
                      </div>
                    </div>

                    <div className="rounded-xl border border-white/10 bg-white/5 p-6">
                      <div className="mb-4 flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
                        <h2 className="text-lg font-semibold text-white">
                          Equity Curve
                        </h2>
                        {filteredTrades.length > 0 ? (
                          <p
                            className={`text-xl font-bold tabular-nums ${
                              currentEquity >= 0
                                ? "text-green-400"
                                : "text-red-400"
                            }`}
                          >
                            {formatMoney(currentEquity)}
                          </p>
                        ) : null}
                      </div>

                      <div className="h-64">
                        <ResponsiveContainer width="100%" height="100%">
                          <LineChart data={equityData}>
                            <CartesianGrid stroke="#1f2937" />
                            <XAxis dataKey="index" hide />
                            <YAxis
                              tick={{ fill: "#cbd5e1", fontSize: 12 }}
                              tickFormatter={(value) => {
                                const n = Number(value)
                                if (!Number.isFinite(n)) return "$0"
                                if (n < 0) {
                                  return `-$${Math.abs(n).toLocaleString()}`
                                }
                                return `$${n.toLocaleString()}`
                              }}
                            />
                            <Tooltip
                              contentStyle={{
                                backgroundColor: "#0f172a",
                                border: "1px solid rgba(255,255,255,0.12)",
                                borderRadius: "0.5rem",
                              }}
                              labelStyle={{ color: "#cbd5e1" }}
                              formatter={(value) => {
                                const n = Number(value)
                                if (!Number.isFinite(n)) return ["$0", "Equity"]
                                const formatted =
                                  n < 0
                                    ? `-$${Math.abs(n).toLocaleString(undefined, {
                                        minimumFractionDigits: 2,
                                        maximumFractionDigits: 2,
                                      })}`
                                    : `$${n.toLocaleString(undefined, {
                                        minimumFractionDigits: 2,
                                        maximumFractionDigits: 2,
                                      })}`
                                return [formatted, "Equity"]
                              }}
                            />
                            <Line
                              type="monotone"
                              dataKey="equity"
                              stroke="#22c55e"
                              strokeWidth={2}
                              dot={false}
                            />
                          </LineChart>
                        </ResponsiveContainer>
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}
          </div>

        </div>

      </div>

      {showCreatePost &&
        profile &&
        currentUserId === profile.id && (
          <div
            className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md"
            role="presentation"
            onClick={() => {
              setShowCreatePost(false)
              setPostContent("")
              setPostImage(null)
            }}
          >
            <div
              className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-2xl"
              role="dialog"
              aria-modal="true"
              aria-labelledby="create-post-title"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="mb-3 flex items-center justify-between">
                <h2
                  id="create-post-title"
                  className="text-lg font-semibold text-white"
                >
                  Create Post
                </h2>

                <button
                  type="button"
                  onClick={() => {
                    setShowCreatePost(false)
                    setPostContent("")
                    setPostImage(null)
                  }}
                  className="rounded p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
                  aria-label="Close"
                >
                  ✕
                </button>
              </div>

              <textarea
                value={postContent}
                onChange={(e) => setPostContent(e.target.value)}
                placeholder="What's on your mind?"
                rows={4}
                className="mb-3 w-full resize-none rounded-lg border border-white/10 bg-[#020617] p-2 text-sm text-white placeholder:text-gray-500"
              />

              <input
                type="file"
                accept="image/*"
                onChange={(e) =>
                  setPostImage(e.target.files?.[0] ?? null)
                }
                className="mb-3 block w-full text-sm text-gray-300 file:mr-2 file:rounded file:border-0 file:bg-white/10 file:px-3 file:py-1.5 file:text-sm file:text-gray-100"
              />

              <button
                type="button"
                onClick={() => void handleCreatePost()}
                disabled={creatingPost}
                className="w-full rounded-lg bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 disabled:opacity-50"
              >
                {creatingPost ? "Posting…" : "Post"}
              </button>
            </div>
          </div>
        )}

      {showStoryModal && (
        <div
          className="fixed inset-0 bg-black/40 backdrop-blur-sm flex items-center justify-center z-50"
          onClick={() => setShowStoryModal(false)}
        >
          <div
            className="bg-[#1e2a4a] border border-white/10 shadow-xl p-6 rounded-xl w-[400px]"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="text-lg font-semibold mb-4 text-white">Create Story</h2>

            <input
              type="file"
              accept="image/*"
              className="text-sm text-white file:bg-blue-500 file:text-white file:px-3 file:py-1 file:rounded file:border-none"
            />

            <div className="flex justify-end gap-2 mt-4">
              <button
                type="button"
                onClick={() => setShowStoryModal(false)}
                className="px-3 py-1 rounded bg-white/10 hover:bg-white/20 text-white"
              >
                Cancel
              </button>

              <button
                type="button"
                className="bg-blue-500 hover:bg-blue-600 px-4 py-2 rounded text-white font-medium"
              >
                Post Story
              </button>
            </div>
          </div>
        </div>
      )}

      {editingPost ? (
        <div
          className="fixed inset-0 z-[200] flex items-center justify-center bg-black/70 p-4 backdrop-blur-md"
          role="presentation"
          onClick={() => setEditingPost(null)}
        >
          <div
            className="w-full max-w-[400px] rounded-xl border border-white/10 bg-[#0f172a] p-6"
            role="dialog"
            aria-modal="true"
            aria-labelledby="edit-post-title"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between">
              <h2 id="edit-post-title" className="text-lg font-semibold text-white">
                Edit Post
              </h2>
              <button
                type="button"
                onClick={() => setEditingPost(null)}
                className="rounded p-1.5 text-gray-400 hover:bg-white/10 hover:text-white"
              >
                ✕
              </button>
            </div>
            <textarea
              value={editContent}
              onChange={(e) => setEditContent(e.target.value)}
              className="mb-3 w-full rounded border border-white/10 bg-[#020617] p-2 text-sm text-white"
              rows={4}
            />
            <button
              type="button"
              onClick={() => void handleUpdatePost()}
              className="w-full rounded bg-blue-500 px-4 py-2 text-sm font-medium text-white hover:bg-blue-600"
            >
              Save Changes
            </button>
          </div>
        </div>
      ) : null}

      {editingTrade ? (
        <InputTradeForm
          existingTrade={editingTrade}
          onClose={() => setEditingTrade(null)}
          onSave={() => {
            if (profile?.id) {
              setPage(0)
              setHasMore(true)
              void fetchTrades(profile.id, true)
            }
            setEditingTrade(null)
          }}
        />
      ) : null}

      {showFollowers && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
          onClick={closeFollowModals}
        >
          <div
            className="max-h-[400px] w-80 overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-4 text-lg font-semibold text-gray-100">Followers</h2>

            {followersModalUsers.length === 0 ? (
              <p className="text-sm text-gray-400">No followers yet.</p>
            ) : (
              <div className="space-y-1">
                {followersModalUsers.map((u) => (
                  <div
                    key={u.id}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
                    onClick={() => {
                      closeFollowModals()
                      router.push(`/profile/${u.id}`)
                    }}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      onError={(e) => {
                        e.currentTarget.src = "/default-avatar.png"
                      }}
                      className="h-8 w-8 rounded-full object-cover"
                    />
                    <span className="text-white">{u.username}</span>
                  </div>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={closeFollowModals}
              className="mt-4 w-full rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20"
            >
              Close
            </button>
          </div>
        </div>
      )}

      {showFollowing && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm"
          onClick={closeFollowModals}
        >
          <div
            className="max-h-[400px] w-80 overflow-y-auto rounded-xl border border-white/10 bg-[#0f172a] p-6 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <h2 className="mb-4 text-lg font-semibold text-gray-100">Following</h2>

            {followingModalUsers.length === 0 ? (
              <p className="text-sm text-gray-400">Not following anyone yet.</p>
            ) : (
              <div className="space-y-1">
                {followingModalUsers.map((u) => (
                  <div
                    key={u.id}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
                    onClick={() => {
                      closeFollowModals()
                      router.push(`/profile/${u.id}`)
                    }}
                  >
                    <img
                      src={u.avatar_url || "/default-avatar.png"}
                      alt=""
                      onError={(e) => {
                        e.currentTarget.src = "/default-avatar.png"
                      }}
                      className="h-8 w-8 rounded-full object-cover"
                    />
                    <span className="text-white">{u.username}</span>
                  </div>
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={closeFollowModals}
              className="mt-4 w-full rounded-lg bg-white/10 p-2 text-white transition hover:bg-white/20"
            >
              Close
            </button>
          </div>
        </div>
      )}

    </>
  )
}

function Stat({ title, value, positive }: any) {
  let color = "text-gray-100"
  if (positive === true) color = "text-green-400"
  if (positive === false) color = "text-red-400"

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center">
      <p className="text-xs text-blue-300">{title}</p>
      <p className={`text-lg font-semibold ${color}`}>{value}</p>
    </div>
  )
}
