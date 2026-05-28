"use client"

import Navbar from "../../components/Navbar"
import AchievementCard from "../../components/AchievementCard"
import type { ChangeEvent } from "react"
import { useCallback, useEffect, useState } from "react"
import { supabase } from "../../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
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
import {
  TradeSocialProvider,
  TradeSocialEngagementBar,
  TradeSocialCommentsSection,
} from "../../components/TradeSocialLayer"
import ShareTradeButton from "../../components/ShareTradeButton"
import InputTradeForm from "../../components/InputTradeForm"
import Calendar from "../../components/Calendar"
import {
  type Achievement,
  fetchOwnAchievements,
  fetchVisibleProfileAchievements,
  formatAchievementDate,
} from "../../../lib/achievements"
import { formatPnlCurrency } from "../../../lib/formatMoney"
import { formatDateOnly, formatTimeOnly } from "@/lib/formatDate"
import { formatEST } from "@/lib/formatEST"
import { createUserRoom } from "@/lib/createUserRoom"
import { handleSupabaseError } from "@/lib/handleSupabaseError"

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

function getDuration(
  start: string | null | undefined,
  end: string | null | undefined
) {
  if (!start || !end) return null

  const diff = +new Date(String(end)) - +new Date(String(start))
  if (!Number.isFinite(diff) || diff <= 0) return null

  const totalSeconds = Math.floor(diff / 1000)

  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  // under 1 minute → force 0m
  if (hours === 0 && minutes === 0) {
    return "0m"
  }

  if (hours === 0) {
    return seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`
  }

  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`
}

function TradeCard({
  trade,
  profile,
  shareProfile,
  canManageTrade,
  menuOpen,
  onMenuToggle,
  onStartEditTrade,
  onTogglePinTrade,
  onSaveTrade,
  onDeleteTrade,
  showInteractions,
  onOpenDetail,
  disableOpen,
}: {
  trade: any
  profile: any
  /** Logged-in viewer profile (referral_code for share PNG) */
  shareProfile?: { referral_code?: string | null } | null
  canManageTrade?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onStartEditTrade?: () => void
  onTogglePinTrade?: () => void
  onSaveTrade?: () => void
  onDeleteTrade?: () => void
  showInteractions?: boolean
  onOpenDetail?: () => void
  disableOpen?: boolean
}) {
  const imageSrc = postImageSrc(trade.image_url)
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const direction = trade.direction ?? "—"
  const ticker = trade.ticker ?? "—"
  const accountTypeNorm = String(trade.account_type ?? "").trim().toLowerCase()
  const rr =
    trade.rr != null && trade.rr !== "" ? trade.rr : "—"
  const pnlLabel = Number.isFinite(pnl)
    ? `${pnl >= 0 ? "+" : ""}${formatMoney(pnl)}`
    : "—"
  const desc = trade.public_description
    ? String(trade.public_description).trim()
    : ""

  const entryRaw = trade.entry_time
  const exitRaw = trade.exit_time
  const entry = entryRaw ? formatTimeOnly(entryRaw) : null
  const exit = exitRaw ? formatTimeOnly(exitRaw) : null
  const duration = getDuration(entryRaw, exitRaw)

  const tradeDetails = (
    <>
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 text-sm text-gray-100">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <span
            className={
              `shrink-0 text-base font-bold tabular-nums ${
                Number.isFinite(pnl)
                  ? pnl >= 0
                    ? "text-emerald-400"
                    : "text-red-400"
                  : "text-gray-400"
              }`
            }
          >
            {pnlLabel}
          </span>

          <span className="min-w-0 truncate font-medium text-white">
            {ticker} · {direction}
          </span>

          {accountTypeNorm ? (
            <span
              className={`
          px-2 py-0.5 text-xs rounded-full font-medium
          ${
            accountTypeNorm === "funded"
              ? "bg-green-500/20 text-green-400 border border-green-400/30"
              : accountTypeNorm === "eval"
                ? "bg-yellow-500/20 text-yellow-300 border border-yellow-400/30"
                : accountTypeNorm === "live"
                  ? "bg-blue-500/20 text-blue-300 border border-blue-400/30"
                  : "bg-white/10 text-white/60"
          }
        `}
            >
              {accountTypeNorm.toUpperCase()}
            </span>
          ) : null}
        </div>
        <span className="shrink-0 text-gray-300 tabular-nums">RR {rr}</span>
      </div>
      {desc ? (
        <p className="px-1 text-sm leading-relaxed text-white">{desc}</p>
      ) : null}
      <p className="text-xs text-gray-400">
        {formatDateOnly(trade.entry_time || trade.created_at || undefined)}
        {entry ? ` • ${entry}` : ""}
        {exit ? ` – ${exit}` : ""}
        {duration ? ` (${duration})` : ""}
      </p>
    </>
  )

  return (
    <article
      className={`h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`}
      role={onOpenDetail && !disableOpen ? "button" : undefined}
      tabIndex={onOpenDetail && !disableOpen ? 0 : undefined}
      onClick={() => {
        if (onOpenDetail && !disableOpen) onOpenDetail()
      }}
      onKeyDown={(e) => {
        if (!onOpenDetail || disableOpen) return
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onOpenDetail()
        }
      }}
    >
      <div className="flex items-center justify-between border-b border-white/5 px-4 py-3">
        <div className="flex min-w-0 items-center gap-3">
          <img
            src={profile.avatar_url || "/default-avatar.png"}
            alt=""
            loading="lazy"
            decoding="async"
            className="h-10 w-10 shrink-0 rounded-full object-cover ring-2 ring-white/10"
            onError={(e) => {
              e.currentTarget.src = "/default-avatar.png"
            }}
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">
              {profile.username || "User"}
            </p>
            <p className="text-xs font-medium text-amber-400/90">
              Trade {trade.is_pinned ? <span className="ml-2 text-yellow-400">📌</span> : null}
            </p>
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <div onClick={(e) => e.stopPropagation()}>
            <ShareTradeButton
              variant="icon"
              trade={trade}
              profile={shareProfile ?? null}
              mode="message-only"
            />
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
      </div>

      {imageSrc ? (
        <div className="relative w-full bg-black/30">
          <img
            src={imageSrc}
            alt=""
            loading="lazy"
            decoding="async"
            className="block max-h-[400px] w-full object-cover"
          />
        </div>
      ) : (
        <div className="flex min-h-[80px] items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] text-xs text-gray-500">
          No screenshot
        </div>
      )}

      {showInteractions ? (
        <div onKeyDown={(e) => e.stopPropagation()}>
          <TradeSocialProvider
            tradeId={trade.id}
            currentUserId={trade.currentUserId}
            tradeOwnerUserId={trade.user_id}
          >
            <div className="border-t border-white/10 px-4 py-2">
              <TradeSocialEngagementBar />
            </div>
            <div className="space-y-3 px-4 pb-3">{tradeDetails}</div>
            <TradeSocialCommentsSection className="px-4 pb-4" />
          </TradeSocialProvider>
        </div>
      ) : (
        <div className="space-y-3 p-4">{tradeDetails}</div>
      )}
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
  onOpenDetail,
  disableOpen,
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
  onOpenDetail?: () => void
  disableOpen?: boolean
}) {
  const imgSrc = profileWallImageSrc(post.image_url)

  return (
    <article
      className={`h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`}
      role={onOpenDetail && !disableOpen ? "button" : undefined}
      tabIndex={onOpenDetail && !disableOpen ? 0 : undefined}
      onClick={() => {
        if (onOpenDetail && !disableOpen) onOpenDetail()
      }}
      onKeyDown={(e) => {
        if (!onOpenDetail || disableOpen) return
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault()
          onOpenDetail()
        }
      }}
    >
      <div className="flex items-center justify-between gap-3 border-b border-white/5 p-4">
        <div className="flex min-w-0 items-center gap-3">
          <img
            src={profile.avatar_url || "/default-avatar.png"}
            alt=""
            loading="lazy"
            decoding="async"
            className="h-10 w-10 rounded-full object-cover ring-2 ring-white/10"
            onError={(e) => {
              e.currentTarget.src = "/default-avatar.png"
            }}
          />
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-white">
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

      {imgSrc ? (
        <div className="w-full bg-black/30">
          <img
            src={imgSrc}
            alt=""
            loading="lazy"
            decoding="async"
            className="block max-h-[400px] w-full object-cover"
            onError={(e) => {
              e.currentTarget.style.display = "none"
            }}
          />
        </div>
      ) : null}

      <div className="space-y-3 p-4">
        {post.content ? (
          <p className="px-1 text-sm leading-relaxed text-white">
            {post.content}
          </p>
        ) : null}

        <p className="text-xs text-gray-400">{formatEST(post.created_at)}</p>
        {showInteractions ? (
          <div className="border-t border-white/10 pt-3">
          <div className="flex items-center gap-4 px-1 text-sm">
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onLike?.()
              }}
              className="flex items-center gap-1 text-gray-300 hover:text-white"
            >
              <span>{likeMeta?.liked ? "❤️" : "🤍"}</span>
              <span className="tabular-nums">{likeMeta?.count ?? 0}</span>
            </button>
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation()
                onToggleComments?.()
              }}
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
                  onClick={(e) => e.stopPropagation()}
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
                  onClick={(e) => {
                    e.stopPropagation()
                    onCommentSubmit?.()
                  }}
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
    </article>
  )
}

export default function ProfilePage() {
  const PAGE_SIZE = 5

  const params = useParams()
  const router = useRouter()
  const rawId = params.id
  const profileId =
    typeof rawId === "string"
      ? rawId.trim() || undefined
      : Array.isArray(rawId)
        ? rawId[0]?.trim() || undefined
        : undefined

  const [profile, setProfile] = useState<any>(null)
  const [trades, setTrades] = useState<any[]>([])
  const [allTrades, setAllTrades] = useState<any[]>([])
  const [page, setPage] = useState(0)
  const [hasMore, setHasMore] = useState(true)
  const [loading, setLoading] = useState(true)
  /** Set when profile row fails to load (wrong env, RLS, missing row, or network). */
  const [lastProfileFetchError, setLastProfileFetchError] = useState<string | null>(
    null
  )
  const [followersCount, setFollowersCount] = useState(0)
  const [followingCount, setFollowingCount] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [viewerShareProfile, setViewerShareProfile] = useState<{
    referral_code?: string | null
  } | null>(null)
  const [isFollowing, setIsFollowing] = useState(false)
  const [followBusy, setFollowBusy] = useState(false)
  const [messageBusy, setMessageBusy] = useState(false)
  const [creatingRoom, setCreatingRoom] = useState(false)
  const [room, setRoom] = useState<any | null>(null)
  const [showFollowers, setShowFollowers] = useState(false)
  const [showFollowing, setShowFollowing] = useState(false)
  const [followersModalUsers, setFollowersModalUsers] = useState<any[]>([])
  const [followingModalUsers, setFollowingModalUsers] = useState<any[]>([])
  const [wallPosts, setWallPosts] = useState<any[]>([])
  const [activeTab, setActiveTab] = useState<
    "trades" | "posts" | "calendar" | "stats" | "achievements"
  >(
    "trades"
  )
  const [showCreatePost, setShowCreatePost] = useState(false)
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
  const [selectedMode, setSelectedMode] = useState("all")
  const [achievements, setAchievements] = useState<Achievement[]>([])
  const [selectedTradeDetail, setSelectedTradeDetail] = useState<any | null>(null)
  const [selectedPostDetail, setSelectedPostDetail] = useState<any | null>(null)
  const [selectedAchievementImage, setSelectedAchievementImage] = useState<{
    src: string
    title: string
    achievedAt: string | null
    description: string | null
  } | null>(null)

  /** Profile Stats equity chart: Recharts props tuned below ~sm breakpoint. */
  const [equityChartNarrow, setEquityChartNarrow] = useState(false)

  useEffect(() => {
    if (typeof window === "undefined") return
    const mq = window.matchMedia("(max-width: 639px)")
    const sync = () => setEquityChartNarrow(mq.matches)
    sync()
    mq.addEventListener("change", sync)
    return () => mq.removeEventListener("change", sync)
  }, [])

  useEffect(() => {
    if (!currentUserId) {
      setViewerShareProfile(null)
      return
    }
    let cancelled = false
    async function load() {
      const { data } = await supabase
        .from("profiles")
        .select("referral_code")
        .eq("id", currentUserId)
        .maybeSingle()
      if (!cancelled) setViewerShareProfile(data ?? null)
    }
    void load()
    return () => {
      cancelled = true
    }
  }, [currentUserId])

  /** Feed refreshes the story bar here; profile has no story strip. */
  const loadFollowingStories = useCallback(async () => {}, [])

  const handleStoryUpload = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      const input = e.target
      const file = input.files?.[0]
      input.value = ""
      if (!file || !currentUserId) return

      let uploadFile: File = file
      if (file.type?.startsWith("image/")) {
        uploadFile = await compressImage(file)
      }
      const fileName = `${currentUserId}/${Date.now()}-${uploadFile.name}`

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
        user_id: currentUserId,
        image_url: publicUrl,
      })

      if (insertError) {
        console.error(insertError)
        alert(insertError.message)
        return
      }

      alert("Story uploaded!")
      await loadFollowingStories()
    },
    [currentUserId, loadFollowingStories]
  )

  const fetchTrades = async (forProfileId: string, reset = false) => {
    const from = reset ? 0 : page * PAGE_SIZE
    const to = from + PAGE_SIZE - 1

    const { data, error } = await supabase
      .from("trades")
      .select("*")
      .eq("user_id", forProfileId)
      .eq("is_public", true)
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
    if (!profile?.id || !currentUserId) {
      setAchievements([])
      return
    }
    let cancelled = false
    async function fetchProfileAchievements() {
      const isOwner = currentUserId === profile.id
      const query = isOwner
        ? await fetchOwnAchievements(profile.id)
        : await fetchVisibleProfileAchievements(profile.id)
      const { data, error } = query
      if (cancelled) return
      if (error) {
        console.error("profile achievements fetch:", error)
        setAchievements([])
        return
      }
      setAchievements((data || []) as Achievement[])
    }
    void fetchProfileAchievements()
    return () => {
      cancelled = true
    }
  }, [profile?.id, currentUserId])

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
    if (
      showCreatePost ||
      editingPost ||
      selectedAchievementImage ||
      selectedTradeDetail ||
      selectedPostDetail
    ) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
    document.body.style.overflow = ""
    return undefined
  }, [showCreatePost, editingPost, selectedAchievementImage, selectedTradeDetail, selectedPostDetail])

  useEffect(() => {
    if (
      !showCreatePost &&
      !editingPost &&
      !selectedAchievementImage &&
      !selectedTradeDetail &&
      !selectedPostDetail
    )
      return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setShowCreatePost(false)
        setEditingPost(null)
        setSelectedAchievementImage(null)
        setSelectedTradeDetail(null)
        setSelectedPostDetail(null)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [showCreatePost, editingPost, selectedAchievementImage, selectedTradeDetail, selectedPostDetail])

  async function fetchProfile(forProfileId: string) {
    const id = forProfileId.trim()
    const devProfileDebug =
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"

    if (devProfileDebug) {
      console.log("SUPABASE URL:", process.env.NEXT_PUBLIC_SUPABASE_URL)
      console.log("FETCHING PROFILE ID:", id)
    }

    setLastProfileFetchError(null)

    const { data: sessionData } = await supabase.auth.getSession()
    const uid = sessionData?.session?.user?.id ?? null
    setCurrentUserId(uid)

    if (devProfileDebug) {
      const listProbe = await supabase.from("profiles").select("*").limit(50)
      console.log("PROFILE DEBUG (list up to 50 rows):", {
        rowCount: listProbe.data?.length ?? 0,
        error: listProbe.error,
        sampleIds: listProbe.data?.slice(0, 5).map((r: { id: string }) => r.id),
      })
    }

    const { data: prof, error } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", id)
      .maybeSingle()

    if (devProfileDebug) {
      console.log("PROFILE DATA:", prof)
      console.log("ERROR:", error)
    }

    if (error) {
      setLastProfileFetchError(
        [error.message, (error as { code?: string }).code]
          .filter(Boolean)
          .join(" ")
      )
    } else if (!prof) {
      setLastProfileFetchError(
        "No row returned (missing id in this DB, or RLS hid the row)."
      )
    }

    if (!prof || error) {
      setProfile(null)
      setRoom(null)
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

    const { data: roomRow, error: roomError } = await supabase
      .from("rooms")
      .select("*")
      .eq("owner_user_id", prof.id)
      .maybeSingle()

    if (roomError) {
      console.error(roomError)
    }

    setRoom(roomRow ?? null)

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

  async function handleCreateRoom() {
    setCreatingRoom(true)

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (!user) return

      const { data: existing, error: existingErr } = await supabase
        .from("rooms")
        .select("*")
        .eq("owner_user_id", user.id)
        .maybeSingle()

      if (existingErr) {
        console.error(existingErr)
      }

      if (existing) {
        setRoom(existing)
        router.push(
          `/trade-rooms?room=${encodeURIComponent(String(existing.slug ?? existing.id))}`
        )
        return
      }

      const { data: profileRow } = await supabase
        .from("profiles")
        .select("username")
        .eq("id", user.id)
        .single()

      const newRoom = await createUserRoom(user.id, profileRow?.username || "user")
      setRoom(newRoom)
      router.push(
        `/trade-rooms?room=${encodeURIComponent(String(newRoom.slug))}&setup=true`
      )
    } catch (err) {
      console.error(err)
    } finally {
      setCreatingRoom(false)
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
      let uploadFile: File = postImage
      if (postImage.type?.startsWith("image/")) {
        uploadFile = await compressImage(postImage)
      }
      const fileName = `${currentUserId}/${Date.now()}-${uploadFile.name}`

      const { error: upErr } = await supabase.storage
        .from("profile_posts")
        .upload(fileName, uploadFile, { upsert: true })

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
      alert(handleSupabaseError(error))
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

  useEffect(() => {
    console.log(allTrades)
  }, [allTrades])

  const filteredTrades = allTrades.filter((trade) => {
    if (selectedMode === "all") return true
    const m = selectedMode.toLowerCase()
    const modeStr = String(trade.mode ?? "").trim().toLowerCase()
    const typeStr = String(trade.account_type ?? "").trim().toLowerCase()
    return modeStr === m || typeStr === m
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
        <div className="w-full flex items-center justify-center text-red-400">
          Invalid profile
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <Navbar />
        <div className="w-full flex items-center justify-center text-gray-400">
          Loading profile...
        </div>
      </>
    )
  }

  if (!profile) {
    const showFetchDebug =
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"

    if (showFetchDebug) {
      return (
        <>
          <Navbar />
          <div className="mx-auto max-w-lg px-4 py-8 text-center text-red-400">
            <div>Profile not found (debug)</div>
            {lastProfileFetchError ? (
              <p className="mt-3 text-left text-xs font-mono text-red-300/90 whitespace-pre-wrap break-all">
                {lastProfileFetchError}
              </p>
            ) : null}
            <p className="mt-3 text-xs text-gray-500">
              Compare NEXT_PUBLIC_SUPABASE_URL with production. If the list probe
              in the console shows rows but this id returns nothing, suspect RLS
              or a UUID that exists only in the other project.
            </p>
          </div>
        </>
      )
    }

    return (
      <>
        <Navbar />
        <div className="w-full flex items-center justify-center text-red-400">
          User not found
        </div>
      </>
    )
  }

  const isOwnProfile = currentUserId === profile.id
  const hasRoom = !!room

  return (
    <>
      <Navbar />

      <div className="w-full text-gray-100">
        <div className="mx-auto max-w-5xl space-y-4 px-4 py-6 sm:px-6 lg:px-8">
          <div className="bg-white/5 border border-white/10 rounded-xl p-6 backdrop-blur-md">
            <div className="flex flex-col items-center text-center sm:items-stretch sm:text-left md:block">
              <div className="flex w-full flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div className="flex min-w-0 w-full flex-1 flex-col items-center gap-2 sm:flex-row sm:items-center sm:gap-6">
                  <img
                    src={profile.avatar_url || "/default-avatar.png"}
                    alt=""
                    onError={(e) => {
                      e.currentTarget.src = "/default-avatar.png"
                    }}
                    className="h-20 w-20 shrink-0 rounded-full border border-white/10 object-cover md:h-24 md:w-24"
                  />

                  <div className="flex min-w-0 w-full flex-1 flex-col justify-center text-center sm:text-left">
                    <div className="flex flex-col items-center gap-2 sm:block">
                      <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start sm:gap-3">
                        <div className="flex items-center justify-center gap-2 sm:justify-start">
                          <h2 className="text-lg font-semibold text-white md:text-xl">
                            {profile.name || profile.username || "User"}
                          </h2>

                          {currentUserId === profile.id && (
                            <div className="flex items-center gap-2">
                              <button
                                type="button"
                                onClick={() => router.push("/settings")}
                                className="rounded-md bg-gray-600 px-2 py-1 text-xs text-gray-100 hover:bg-gray-500 md:bg-white/10 md:px-3 md:text-sm md:hover:bg-white/20"
                              >
                                Settings
                              </button>
                            </div>
                          )}
                        </div>

                        {currentUserId && currentUserId !== profile.id && (
                          <div className="flex w-full flex-wrap items-center justify-center gap-2 sm:w-auto sm:justify-start">
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
                          </div>
                        )}
                      </div>

                    </div>

                  <p className="mt-1 text-sm text-gray-400">{profile.username}</p>

                  <p className="mt-1 text-sm text-gray-400">
                    {profile.trading_style ||
                      profile.trading_model ||
                      "—"}{" "}
                    • {getExperience(profile.started_trading) || "N/A"}
                  </p>

                  <div className="mt-4 flex w-full items-center justify-between px-4 text-center text-sm md:hidden md:text-base">
                    <div className="flex min-h-[44px] flex-1 flex-col items-center justify-center">
                      <span className="text-[15px] font-semibold tabular-nums text-white">
                        {statsVisible ? totalTrades : "—"}
                      </span>
                      <span className="text-[11px] text-gray-400">Trades</span>
                    </div>
                    <button
                      type="button"
                      onClick={() => openFollowersModal()}
                      className="relative z-10 flex min-h-[44px] flex-1 cursor-pointer flex-col items-center justify-center rounded-md px-2 py-1 active:scale-95"
                    >
                      <span className="text-[15px] font-semibold tabular-nums text-white">
                        {followersCount}
                      </span>
                      <span className="text-[11px] text-gray-400">Followers</span>
                    </button>
                    <button
                      type="button"
                      onClick={() => openFollowingModal()}
                      className="relative z-10 flex min-h-[44px] flex-1 cursor-pointer flex-col items-center justify-center rounded-md px-2 py-1 active:scale-95"
                    >
                      <span className="text-[15px] font-semibold tabular-nums text-white">
                        {followingCount}
                      </span>
                      <span className="text-[11px] text-gray-400">Following</span>
                    </button>
                  </div>

                  <div className="mt-2 hidden flex-wrap items-center justify-center gap-4 text-sm text-gray-400 sm:flex sm:justify-start">
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

                  <p className="mt-2 px-4 text-sm leading-relaxed text-gray-300 md:px-0">
                    {profile.bio || "No bio yet"}
                  </p>

                  {isOwnProfile ? (
                    hasRoom ? (
                      <div className="mt-3">
                        <button
                          type="button"
                          onClick={() =>
                            router.push(
                              `/trade-rooms?room=${encodeURIComponent(
                                String(room.slug ?? room.id)
                              )}`
                            )
                          }
                          className="px-6 py-2 rounded-lg bg-green-500 font-semibold text-sm text-white hover:bg-green-600"
                        >
                          View Trade Room
                        </button>
                      </div>
                    ) : (
                      <div className="mt-3">
                        <button
                          type="button"
                          onClick={() => void handleCreateRoom()}
                          disabled={creatingRoom}
                          className="px-6 py-2 rounded-lg bg-green-500 font-semibold text-sm text-white hover:bg-green-600 disabled:opacity-60"
                        >
                          {creatingRoom ? "Creating…" : "Create Trade Room"}
                        </button>
                      </div>
                    )
                  ) : room &&
                    room.show_on_profile !== false &&
                    (room.slug || room.name) ? (
                    <div className="mt-3">
                      <button
                        type="button"
                        onClick={() =>
                          router.push(
                            `/trade-rooms?room=${encodeURIComponent(
                              String(room.slug ?? room.name ?? room.id)
                            )}`
                          )
                        }
                        className="px-6 py-2 rounded-lg bg-green-500 font-semibold text-sm text-white hover:bg-green-600"
                      >
                        View Trade Room
                      </button>
                    </div>
                  ) : null}
                </div>
              </div>

              {currentUserId === profile.id && (
                <>
                  <input
                    id="storyUploadInput"
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={(e) => void handleStoryUpload(e)}
                  />
                  <div className="mt-0 flex w-full shrink-0 justify-center gap-2 sm:mt-0 sm:w-auto sm:justify-end sm:pt-1 md:w-auto">
                    <button
                      type="button"
                      onClick={() =>
                        document.getElementById("storyUploadInput")?.click()
                      }
                      className="flex-1 rounded-md bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 sm:flex-none sm:py-1.5 sm:text-xs"
                    >
                      + Story
                    </button>
                    <button
                      type="button"
                      onClick={() => setShowCreatePost(true)}
                      className="flex-1 rounded-md bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600 sm:flex-none sm:py-1.5 sm:text-xs"
                    >
                      + Post
                    </button>
                  </div>
                </>
              )}
            </div>
            </div>
          </div>

          <div className="hidden grid-cols-2 gap-3 md:grid md:grid-cols-4 md:gap-4">
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

          <div className="mt-4 flex justify-around border-b border-white/10 sm:mt-6 sm:justify-start sm:gap-6 sm:pb-2">
            <button
              type="button"
              className={`text-sm font-medium border-b-2 py-2 sm:py-0 ${
                activeTab === "trades"
                  ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
                  : "border-transparent text-gray-400 sm:border-b-0"
              }`}
              onClick={() => setActiveTab("trades")}
            >
              Trades
            </button>

            <button
              type="button"
              className={`text-sm font-medium border-b-2 py-2 sm:py-0 ${
                activeTab === "posts"
                  ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
                  : "border-transparent text-gray-400 sm:border-b-0"
              }`}
              onClick={() => setActiveTab("posts")}
            >
              Posts
            </button>

            <button
              type="button"
              className={`text-sm font-medium border-b-2 py-2 sm:py-0 ${
                activeTab === "stats"
                  ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
                  : "border-transparent text-gray-400 sm:border-b-0"
              }`}
              onClick={() => setActiveTab("stats")}
            >
              Stats
            </button>

            <button
              type="button"
              className={`text-sm font-medium border-b-2 py-2 sm:py-0 ${
                activeTab === "calendar"
                  ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
                  : "border-transparent text-gray-400 sm:border-b-0"
              }`}
              onClick={() => setActiveTab("calendar")}
            >
              Calendar
            </button>
            <button
              type="button"
              className={`text-sm font-medium border-b-2 py-2 sm:py-0 ${
                activeTab === "achievements"
                  ? "border-blue-400 text-white sm:border-blue-500 sm:pb-1"
                  : "border-transparent text-gray-400 sm:border-b-0"
              }`}
              onClick={() => setActiveTab("achievements")}
            >
              Achievements
            </button>
          </div>

          <div className="mt-3 space-y-6 px-2 md:mt-4 md:px-0">
            {activeTab === "trades" && (
              <div className="mt-4 w-full pb-8">
                {sortedTrades.length === 0 ? (
                  <p className="text-center text-sm text-gray-400">
                    {currentUserId === profile.id
                      ? "No trades yet."
                      : "No trades yet."}
                  </p>
                ) : (
                  <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
                    {sortedTrades.map((trade) => (
                      <TradeCard
                        key={trade.id}
                        trade={{ ...trade, currentUserId }}
                        profile={profile}
                        shareProfile={viewerShareProfile}
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
                        onOpenDetail={() =>
                          setSelectedTradeDetail({ ...trade, currentUserId })
                        }
                      />
                    ))}
                  </div>
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
              <div className="mt-4 w-full pb-8">
                {sortedPosts.length === 0 ? (
                  <p className="text-center text-sm text-gray-400">
                    No posts yet.
                  </p>
                ) : (
                  <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
                    {sortedPosts.map((post) => {
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
                          onOpenDetail={() => setSelectedPostDetail(post)}
                        />
                      )
                    })}
                  </div>
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
                    <div className="mb-4 flex items-center justify-between">
                      <div className="flex flex-wrap items-center gap-2 md:gap-3">
                        {(
                          [
                            { id: "all", label: "All" },
                            { id: "eval", label: "Eval" },
                            { id: "funded", label: "Funded" },
                            { id: "live", label: "Live" },
                            { id: "backtest", label: "Backtest" },
                          ] as const
                        ).map(({ id, label }) => (
                          <button
                            key={id}
                            type="button"
                            onClick={() => setSelectedMode(id)}
                            className={`px-4 py-1.5 rounded-lg text-sm font-medium transition ${
                              selectedMode === id
                                ? "bg-blue-500 text-white"
                                : "bg-white/5 text-white/70 hover:bg-white/10"
                            }`}
                          >
                            {label}
                          </button>
                        ))}
                      </div>
                      <div />
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
                        <p className="font-semibold text-green-400 tabular-nums">
                          {formatPnlCurrency(biggestWin)}
                        </p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Biggest Loss</p>
                        <p className="font-semibold text-red-400 tabular-nums">
                          {formatPnlCurrency(biggestLoss)}
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

                    <div className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-6">
                      <div className="mb-3 flex flex-col gap-1 sm:mb-4 sm:flex-row sm:items-end sm:justify-between">
                        <h2 className="text-lg font-semibold text-white">
                          Equity Curve
                        </h2>
                        {filteredTrades.length > 0 ? (
                          <p
                            className={`text-lg font-bold tabular-nums sm:text-xl ${
                              currentEquity >= 0
                                ? "text-green-400"
                                : "text-red-400"
                            }`}
                          >
                            {formatMoney(currentEquity)}
                          </p>
                        ) : null}
                      </div>

                      <div
                        className={`w-full md:h-64 ${
                          equityChartNarrow
                            ? "h-[min(52vw,340px)] min-h-[280px]"
                            : "h-72"
                        }`}
                      >
                        <ResponsiveContainer width="100%" height="100%">
                          <LineChart
                            data={equityData}
                            margin={
                              equityChartNarrow
                                ? { top: 12, right: 8, left: 4, bottom: 12 }
                                : { top: 8, right: 16, left: 12, bottom: 8 }
                            }
                          >
                            <CartesianGrid stroke="rgba(148, 163, 184, 0.08)" />
                            <XAxis dataKey="index" hide />
                            <YAxis
                              width={equityChartNarrow ? 50 : undefined}
                              tickCount={equityChartNarrow ? 5 : 7}
                              axisLine={{
                                stroke: "rgba(148, 163, 184, 0.1)",
                              }}
                              tickLine={{
                                stroke: "rgba(148, 163, 184, 0.08)",
                              }}
                              tick={{
                                fill: "#cbd5e1",
                                fontSize: equityChartNarrow ? 10 : 12,
                              }}
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
                              strokeWidth={equityChartNarrow ? 2.5 : 2}
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

            {activeTab === "achievements" && (
              <div className="space-y-4">
                {achievements.length === 0 ? (
                  <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center">
                    <p className="text-sm text-gray-300">
                      {currentUserId === profile.id
                        ? "No achievements yet."
                        : "No public achievements yet."}
                    </p>
                  </div>
                ) : (
                  <>
                    {achievements.some((a) => a.is_featured) ? (
                      <div className="space-y-2">
                        <h3 className="text-sm font-semibold text-white">Featured</h3>
                        <div className="grid gap-3 sm:grid-cols-2">
                          {achievements
                            .filter((a) => a.is_featured)
                            .map((a) => {
                              return (
                              <AchievementCard
                                key={a.id}
                                achievement={a}
                                featured
                                showVisibility={false}
                                onImageClick={(src, achievement) =>
                                  setSelectedAchievementImage({
                                    src,
                                    title: achievement.title,
                                    achievedAt: achievement.achieved_at,
                                    description: achievement.description,
                                  })
                                }
                              />
                              )
                            })}
                        </div>
                      </div>
                    ) : null}
                    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                      {achievements.map((a) => {
                        return (
                        <AchievementCard
                          key={a.id}
                          achievement={a}
                          onImageClick={(src, achievement) =>
                            setSelectedAchievementImage({
                              src,
                              title: achievement.title,
                              achievedAt: achievement.achieved_at,
                              description: achievement.description,
                            })
                          }
                        />
                        )
                      })}
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

      {selectedAchievementImage ? (
        <div
          className="fixed inset-0 z-[210] flex items-center justify-center bg-black/80 p-3 backdrop-blur-md sm:p-5"
          role="presentation"
          onClick={() => setSelectedAchievementImage(null)}
        >
          <div
            className="w-full max-w-4xl rounded-2xl border border-white/10 bg-gradient-to-br from-[#0f172a] via-[#0b1532] to-[#0a2230] p-3 shadow-2xl shadow-blue-900/20 sm:p-4"
            role="dialog"
            aria-modal="true"
            aria-label="Achievement image preview"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-2 flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold text-white">
                  {selectedAchievementImage.title}
                </p>
                <p className="text-xs text-gray-400">
                  {formatAchievementDate(selectedAchievementImage.achievedAt)}
                </p>
              </div>
              <button
                type="button"
                onClick={() => setSelectedAchievementImage(null)}
                className="rounded-md p-1.5 text-gray-300 hover:bg-white/10 hover:text-white"
                aria-label="Close preview"
              >
                ✕
              </button>
            </div>
            <img
              src={selectedAchievementImage.src}
              alt={selectedAchievementImage.title}
              loading="lazy"
              decoding="async"
              className="max-h-[75vh] w-full rounded-xl border border-white/10 object-contain bg-black/30"
            />
            {selectedAchievementImage.description ? (
              <p className="mt-2 text-sm text-gray-300">
                {selectedAchievementImage.description}
              </p>
            ) : null}
          </div>
        </div>
      ) : null}

      {selectedTradeDetail ? (
        <div
          className="fixed inset-0 z-[205] flex items-center justify-center bg-black/75 p-3 backdrop-blur-md sm:p-4"
          role="presentation"
          onClick={() => setSelectedTradeDetail(null)}
        >
          <div
            className="relative max-h-[92vh] w-full max-w-2xl overflow-y-auto"
            role="dialog"
            aria-modal="true"
            aria-label="Trade details"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setSelectedTradeDetail(null)}
              className="absolute right-2 top-2 z-10 rounded-md bg-black/50 px-2 py-1 text-sm text-white hover:bg-black/70"
              aria-label="Close trade details"
            >
              ✕
            </button>
            <TradeCard
              trade={selectedTradeDetail}
              profile={profile}
              shareProfile={viewerShareProfile}
              canManageTrade={currentUserId === profile.id}
              menuOpen={openTradeMenuId === String(selectedTradeDetail.id)}
              onMenuToggle={() =>
                setOpenTradeMenuId((prev) =>
                  prev === String(selectedTradeDetail.id)
                    ? null
                    : String(selectedTradeDetail.id)
                )
              }
              onStartEditTrade={() => {
                openEditTradeModal(selectedTradeDetail)
                setOpenTradeMenuId(null)
                setSelectedTradeDetail(null)
              }}
              onTogglePinTrade={() => void handlePinTrade(selectedTradeDetail)}
              onSaveTrade={() => void handleSaveTrade(String(selectedTradeDetail.id))}
              onDeleteTrade={() => void handleDeleteTrade(String(selectedTradeDetail.id))}
              showInteractions={true}
              disableOpen
            />
          </div>
        </div>
      ) : null}

      {selectedPostDetail ? (
        <div
          className="fixed inset-0 z-[205] flex items-center justify-center bg-black/75 p-3 backdrop-blur-md sm:p-4"
          role="presentation"
          onClick={() => setSelectedPostDetail(null)}
        >
          <div
            className="relative max-h-[92vh] w-full max-w-2xl overflow-y-auto"
            role="dialog"
            aria-modal="true"
            aria-label="Post details"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setSelectedPostDetail(null)}
              className="absolute right-2 top-2 z-10 rounded-md bg-black/50 px-2 py-1 text-sm text-white hover:bg-black/70"
              aria-label="Close post details"
            >
              ✕
            </button>
            <PostCard
              post={selectedPostDetail}
              profile={profile}
              canManagePost={currentUserId === profile.id}
              menuOpen={openMenuId === String(selectedPostDetail.id)}
              onMenuToggle={() =>
                setOpenMenuId((prev) =>
                  prev === String(selectedPostDetail.id)
                    ? null
                    : String(selectedPostDetail.id)
                )
              }
              onStartEditPost={() => {
                setEditingPost(selectedPostDetail)
                setEditContent(selectedPostDetail.content || "")
                setOpenMenuId(null)
                setSelectedPostDetail(null)
              }}
              onTogglePinPost={() => void handlePinPost(selectedPostDetail)}
              onSavePost={() => void handleSavePost(String(selectedPostDetail.id))}
              onDeletePost={() => void handleDeletePost(String(selectedPostDetail.id))}
              showInteractions={true}
              onLike={() => void handleLike(String(selectedPostDetail.id), "post")}
              onToggleComments={() => openComments(String(selectedPostDetail.id), "post")}
              commentsOpen={!!openCommentsState[`post:${String(selectedPostDetail.id)}`]}
              likeMeta={likesByPost[String(selectedPostDetail.id)] || { count: 0, liked: false }}
              comments={commentsByPost[String(selectedPostDetail.id)] || []}
              commentText={commentDraft[String(selectedPostDetail.id)] || ""}
              onCommentChange={(value) =>
                setCommentDraft((prev) => ({
                  ...prev,
                  [String(selectedPostDetail.id)]: value,
                }))
              }
              onCommentSubmit={() => void submitComment(String(selectedPostDetail.id), "post")}
              commentSubmitting={!!commentSubmitting[String(selectedPostDetail.id)]}
              disableOpen
            />
          </div>
        </div>
      ) : null}

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
                      loading="lazy"
                      decoding="async"
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
                      loading="lazy"
                      decoding="async"
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
