"use client"

import Navbar from "../../components/Navbar"
import AchievementCard from "../../components/AchievementCard"
import type { ChangeEvent } from "react"
import {
  Suspense,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import { supabase } from "../../../lib/supabaseClient"
import { compressImage } from "@/lib/compressImage"
import { normalizeTraderType } from "@/lib/traderType"
import { useParams, useRouter, useSearchParams } from "next/navigation"
import FeedPostDetailModal from "../../components/feed/FeedPostDetailModal"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "../../components/ui/DetailModalShell"
import { EMPTY_LIKE_META } from "../../components/feed/FeedPostCard"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_COMMENTS_SELECT,
  FEED_POSTS_SELECT,
} from "../../components/feed/feedPostHelpers"
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
import { formatRR } from "@/lib/formatDisplay"
import TradeCardTimingBlock from "../../components/TradeCardTimingBlock"
import { formatEST } from "@/lib/formatEST"
import { createUserRoom } from "@/lib/createUserRoom"
import { loadFollowUiSnapshot } from "@/lib/followActions"
import FollowButton from "../../components/FollowButton"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { ensureDmConversation } from "@/lib/dmConversation"
import { dmThreadPath } from "@/lib/messageRoutes"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import StoryComposeModal from "../../components/feed/StoryComposeModal"
import { publishStory } from "@/lib/publishStory"
import {
  createStoryPreviewUrl,
  prepareStoryImageFile,
  revokeStoryPreviewUrl,
} from "@/lib/storyComposeHelpers"
import { isProfileUuidSegment, profilePath } from "@/lib/profileRoutes"
import { normalizeProfileUsername } from "@/lib/profileUsername"

function postImageSrc(imageUrl: string | null | undefined): string | null {
  const raw = imageUrl != null ? String(imageUrl).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

function formatPostFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
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

function formatProfileMetadataLine(profile: {
  trading_style?: string | null
  trading_model?: string | null
  trader_type?: string | null
  primary_market?: string | null
  started_trading?: string | null
}) {
  const parts: string[] = [
    profile.trading_style?.trim() ||
      profile.trading_model?.trim() ||
      "—",
  ]
  const traderType = normalizeTraderType(profile.trader_type)
  if (traderType) parts.push(traderType)
  const market = profile.primary_market?.trim()
  if (market) parts.push(market)
  parts.push(getExperience(profile.started_trading) || "N/A")
  return parts.join(" • ")
}

function formatMoney(v: number) {
  return v < 0
    ? `-$${Math.abs(v).toLocaleString(undefined, { minimumFractionDigits: 2 })}`
    : `$${v.toLocaleString(undefined, { minimumFractionDigits: 2 })}`
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
  onOpenComments,
  commentsExpanded = false,
  scrollToCommentsOnMount = false,
  inDetailModal = false,
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
  onOpenComments?: () => void
  commentsExpanded?: boolean
  scrollToCommentsOnMount?: boolean
  inDetailModal?: boolean
  disableOpen?: boolean
}) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const imageSrc = postImageSrc(trade.image_url)
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const direction = trade.direction ?? "—"
  const ticker = trade.ticker ?? "—"
  const accountTypeNorm = String(trade.account_type ?? "").trim().toLowerCase()
  const rr =
    trade.rr != null && trade.rr !== "" ? formatRR(trade.rr) : "—"
  const pnlLabel = Number.isFinite(pnl)
    ? `${pnl >= 0 ? "+" : ""}${formatMoney(pnl)}`
    : "—"
  const desc = trade.public_description
    ? String(trade.public_description).trim()
    : ""

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
      <TradeCardTimingBlock trade={trade} />
    </>
  )

  const cardShellClass = inDetailModal
    ? "flex min-h-0 flex-1 flex-col overflow-hidden bg-transparent"
    : `h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`

  return (
    <article
      className={cardShellClass}
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
      <div
        className={
          inDetailModal
            ? "shrink-0"
            : undefined
        }
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
            className={`block w-full object-cover ${
              inDetailModal ? "max-h-[22dvh]" : "max-h-[400px]"
            }`}
          />
        </div>
      ) : (
        <div className="flex min-h-[80px] items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] text-xs text-gray-500">
          No screenshot
        </div>
      )}
      </div>

      {showInteractions ? (
        <div
          className={inDetailModal ? "flex min-h-0 flex-1 flex-col overflow-hidden" : undefined}
          onKeyDown={(e) => e.stopPropagation()}
        >
          <TradeSocialProvider
            tradeId={trade.id}
            currentUserId={trade.currentUserId}
            tradeOwnerUserId={trade.user_id}
            commentsExpanded={commentsExpanded}
            onRequestComments={commentsExpanded ? undefined : onOpenComments}
            scrollToCommentsOnMount={scrollToCommentsOnMount}
          >
            {inDetailModal ? (
              <>
                <div className="shrink-0">
                  <div className="border-t border-white/10 px-4 py-2">
                    <TradeSocialEngagementBar />
                  </div>
                  <div className="space-y-3 px-4 pb-3 pt-4">{tradeDetails}</div>
                </div>
                {commentsExpanded ? (
                  <div className="flex min-h-0 flex-1 flex-col overflow-hidden border-t border-white/10">
                    <TradeSocialCommentsSection
                      className="px-4 pb-4"
                      scrollContainerRef={commentsScrollRef}
                    />
                  </div>
                ) : null}
              </>
            ) : (
              <>
                <div className="border-t border-white/10 px-4 py-2">
                  <TradeSocialEngagementBar />
                </div>
                <div className="space-y-3 px-4 pb-3">{tradeDetails}</div>
                {commentsExpanded ? (
                  <TradeSocialCommentsSection className="px-4 pb-4" />
                ) : null}
              </>
            )}
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
  onOpenComments,
  showCommentsPanel,
  scrollToCommentsOnMount,
  likeMeta,
  comments,
  commentText,
  onCommentChange,
  onCommentSubmit,
  commentSubmitting,
  onOpenDetail,
  inDetailModal = false,
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
  onOpenComments?: () => void
  showCommentsPanel?: boolean
  scrollToCommentsOnMount?: boolean
  likeMeta?: { count: number; liked: boolean }
  comments?: any[]
  commentText?: string
  onCommentChange?: (value: string) => void
  onCommentSubmit?: () => void
  commentSubmitting?: boolean
  onOpenDetail?: () => void
  inDetailModal?: boolean
  disableOpen?: boolean
}) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const imgSrc = profileWallImageSrc(post.image_url)

  useEffect(() => {
    if (!showCommentsPanel || !scrollToCommentsOnMount) return
    requestAnimationFrame(() => {
      if (inDetailModal) {
        scrollModalCommentsPane(commentsScrollRef.current)
        return
      }
      const section = document.getElementById(`profile-post-comments-${post.id}`)
      section?.scrollIntoView({ behavior: "smooth", block: "nearest" })
      const input = section?.querySelector("input")
      if (input instanceof HTMLInputElement) input.focus()
    })
  }, [inDetailModal, post.id, scrollToCommentsOnMount, showCommentsPanel])

  const commentsList = (
    <div className="space-y-1 text-sm text-gray-300">
      {(comments || []).map((c: any) => (
        <p key={c.id}>
          <span className="font-medium text-white">
            {c.profiles?.username || "User"}
          </span>{" "}
          {c.content}
        </p>
      ))}
    </div>
  )

  const commentsComposer = (
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
  )

  const commentsPanel = showCommentsPanel ? (
    <div
      id={`profile-post-comments-${post.id}`}
      className="mt-3 space-y-3"
    >
      <div className="max-h-48 space-y-1 overflow-y-auto text-sm text-gray-300">
        {commentsList}
      </div>
      {commentsComposer}
    </div>
  ) : null

  const cardShellClass = inDetailModal
    ? "flex min-h-0 flex-1 flex-col overflow-hidden bg-transparent"
    : `h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`

  return (
    <article
      className={cardShellClass}
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
      <div className={inDetailModal ? "shrink-0" : undefined}>
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
            className={`block w-full object-cover ${
              inDetailModal ? "max-h-[22dvh]" : "max-h-[400px]"
            }`}
            onError={(e) => {
              e.currentTarget.style.display = "none"
            }}
          />
        </div>
      ) : null}
      </div>

      <div className={`space-y-3 p-4 ${inDetailModal ? "shrink-0" : ""}`}>
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
                onOpenComments?.()
                if (inDetailModal && showCommentsPanel) {
                  requestAnimationFrame(() => {
                    scrollModalCommentsPane(commentsScrollRef.current)
                  })
                }
              }}
              className="text-gray-300 hover:text-white"
              aria-label="View comments"
            >
              💬 {comments?.length ?? 0}
            </button>
          </div>
          <p className="px-1 pt-2 text-sm font-medium text-white">
            {(likeMeta?.count ?? 0).toLocaleString()} likes
          </p>
          {!inDetailModal ? commentsPanel : null}
          </div>
        ) : null}
      </div>
      {inDetailModal && showCommentsPanel ? (
        <div
          id={`profile-post-comments-${post.id}`}
          className="flex min-h-0 flex-1 flex-col overflow-hidden border-t border-white/10"
        >
          <div
            ref={commentsScrollRef}
            className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pt-3"
          >
            {commentsList}
          </div>
          <div className="shrink-0 px-4 pb-4 pt-3">{commentsComposer}</div>
        </div>
      ) : null}
    </article>
  )
}

function scrollToProfileTarget(elementId: string) {
  requestAnimationFrame(() => {
    document.getElementById(elementId)?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    })
  })
}

function ProfilePageContent() {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const PAGE_SIZE = 5

  const params = useParams()
  const router = useRouter()
  const searchParams = useSearchParams()
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
  const [isRequested, setIsRequested] = useState(false)
  const [followsYou, setFollowsYou] = useState(false)
  const [messageBusy, setMessageBusy] = useState(false)
  const [creatingRoom, setCreatingRoom] = useState(false)
  const [room, setRoom] = useState<any | null>(null)
  const [showFollowers, setShowFollowers] = useState(false)
  const [showFollowing, setShowFollowing] = useState(false)
  const [followersModalUsers, setFollowersModalUsers] = useState<any[]>([])
  const [followingModalUsers, setFollowingModalUsers] = useState<any[]>([])
  const [wallPosts, setWallPosts] = useState<any[]>([])
  const [wallPostsReady, setWallPostsReady] = useState(false)
  const [activeTab, setActiveTab] = useState<
    "trades" | "posts" | "calendar" | "stats" | "achievements"
  >(
    "trades"
  )
  const [showCreatePost, setShowCreatePost] = useState(false)
  const [storyComposeOpen, setStoryComposeOpen] = useState(false)
  const [pendingStoryFile, setPendingStoryFile] = useState<File | null>(null)
  const [pendingStoryPreviewUrl, setPendingStoryPreviewUrl] = useState<
    string | null
  >(null)
  const [postingStory, setPostingStory] = useState(false)
  const [postContent, setPostContent] = useState("")
  const [postImage, setPostImage] = useState<File | null>(null)
  const [postImagePreviewUrl, setPostImagePreviewUrl] = useState<string | null>(
    null
  )
  const [creatingPost, setCreatingPost] = useState(false)
  const [postDetailFocusComments, setPostDetailFocusComments] = useState(false)
  const [tradeDetailFocusComments, setTradeDetailFocusComments] = useState(false)
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
  const [feedDeepLinkPost, setFeedDeepLinkPost] = useState<any | null>(null)
  const [feedDeepLinkLikeMeta, setFeedDeepLinkLikeMeta] = useState(EMPTY_LIKE_META)
  const [feedDeepLinkComments, setFeedDeepLinkComments] = useState<any[]>([])
  const [feedDeepLinkCommentSubmitting, setFeedDeepLinkCommentSubmitting] =
    useState(false)
  const feedDraftSyncRef = useRef<Record<string, string>>({})
  const feedOpenCommentsRef = useRef<Record<string, boolean>>({})
  const deepLinkHandledRef = useRef<string | null>(null)

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

  useEffect(() => {
    if (!postImage) {
      setPostImagePreviewUrl(null)
      return
    }

    const url = createStoryPreviewUrl(postImage)
    setPostImagePreviewUrl(url)

    return () => {
      revokeStoryPreviewUrl(url)
    }
  }, [postImage])

  /** Feed refreshes the story bar here; profile has no story strip. */
  const loadFollowingStories = useCallback(async () => {}, [])

  useEffect(() => {
    return () => {
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    }
  }, [pendingStoryPreviewUrl])

  const closeStoryCompose = useCallback(() => {
    revokeStoryPreviewUrl(pendingStoryPreviewUrl)
    setPendingStoryPreviewUrl(null)
    setPendingStoryFile(null)
    setStoryComposeOpen(false)
  }, [pendingStoryPreviewUrl])

  const setStoryDraft = useCallback(
    async (file: File) => {
      const prepared = await prepareStoryImageFile(file)
      revokeStoryPreviewUrl(pendingStoryPreviewUrl)
      setPendingStoryFile(prepared)
      setPendingStoryPreviewUrl(createStoryPreviewUrl(prepared))
      setStoryComposeOpen(true)
    },
    [pendingStoryPreviewUrl]
  )

  const handleStoryFileSelect = useCallback(
    async (e: ChangeEvent<HTMLInputElement>) => {
      const input = e.target
      const file = input.files?.[0]
      input.value = ""
      if (!file || !currentUserId) return
      await setStoryDraft(file)
    },
    [currentUserId, setStoryDraft]
  )

  const handlePostStory = useCallback(async () => {
    if (!pendingStoryFile || !currentUserId || postingStory) return
    setPostingStory(true)

    const result = await publishStory(supabase, currentUserId, pendingStoryFile)
    setPostingStory(false)

    if (!result.ok) {
      showPopup({ type: "error", message: result.message })
      return
    }

    showPopup({ type: "success", message: "Story uploaded!" })
    closeStoryCompose()
    await loadFollowingStories()
  }, [
    pendingStoryFile,
    currentUserId,
    postingStory,
    showPopup,
    closeStoryCompose,
    loadFollowingStories,
  ])

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
    deepLinkHandledRef.current = null
  }, [profileId])

  useEffect(() => {
    console.log("Trades:", trades)
  }, [trades])

  useEffect(() => {
    if (!profile?.id) {
      setWallPosts([])
      setWallPostsReady(true)
      return
    }

    let cancelled = false
    setWallPostsReady(false)

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
        setWallPostsReady(true)
        return
      }
      setWallPosts(data || [])
      setWallPostsReady(true)
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
    const isOwner =
      currentUserId != null && String(currentUserId) === String(profile.id)

    async function fetchAllTrades() {
      let query = supabase
        .from("trades")
        .select("*")
        .eq("user_id", profile.id)

      if (!isOwner) {
        query = query.eq("is_public", true)
      }

      const { data, error } = await query

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
  }, [profile?.id, currentUserId])

  useEffect(() => {
    if (!profile?.id) {
      setCalendarTrades([])
      return
    }

    let cancelled = false
    const isOwner =
      currentUserId != null && String(currentUserId) === String(profile.id)

    async function fetchCalendarTrades() {
      let query = supabase
        .from("trades")
        .select("id, created_at, pnl, ticker, direction")
        .eq("user_id", profile.id)

      if (!isOwner) {
        query = query.eq("is_public", true)
      }

      const { data, error } = await query

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
  }, [profile?.id, currentUserId])

  useEffect(() => {
    if (
      showCreatePost ||
      editingPost ||
      selectedAchievementImage ||
      selectedTradeDetail ||
      selectedPostDetail ||
      feedDeepLinkPost
    ) {
      document.body.style.overflow = "hidden"
      return () => {
        document.body.style.overflow = ""
      }
    }
    document.body.style.overflow = ""
    return undefined
  }, [
    showCreatePost,
    editingPost,
    selectedAchievementImage,
    selectedTradeDetail,
    selectedPostDetail,
    feedDeepLinkPost,
  ])

  useEffect(() => {
    if (
      !showCreatePost &&
      !editingPost &&
      !selectedAchievementImage &&
      !selectedTradeDetail &&
      !selectedPostDetail &&
      !feedDeepLinkPost
    )
      return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setShowCreatePost(false)
        setEditingPost(null)
        setSelectedAchievementImage(null)
        setSelectedTradeDetail(null)
        setSelectedPostDetail(null)
        setFeedDeepLinkPost(null)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [showCreatePost, editingPost, selectedAchievementImage, selectedTradeDetail, selectedPostDetail, feedDeepLinkPost])

  async function fetchProfile(urlSegment: string) {
    const segment = urlSegment.trim()
    const lookupByUuid = isProfileUuidSegment(segment)
    const devProfileDebug =
      process.env.NODE_ENV === "development" ||
      process.env.NEXT_PUBLIC_PROFILE_FETCH_DEBUG === "1"

    if (devProfileDebug) {
      console.log("SUPABASE URL:", process.env.NEXT_PUBLIC_SUPABASE_URL)
      console.log("FETCHING PROFILE SEGMENT:", segment, { lookupByUuid })
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

    let profileQuery = supabase.from("profiles").select("*")
    if (lookupByUuid) {
      profileQuery = profileQuery.eq("id", segment)
    } else {
      profileQuery = profileQuery.eq(
        "username",
        normalizeProfileUsername(segment)
      )
    }

    const { data: prof, error } = await profileQuery.maybeSingle()

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
      setIsRequested(false)
      setFollowsYou(false)
      setLoading(false)
      return
    }

    let following = false
    let requested = false
    let profileFollowsYou = false
    if (uid && uid !== prof.id) {
      const snapshot = await loadFollowUiSnapshot(supabase, uid, prof.id)
      following = snapshot.state === "following"
      requested = snapshot.state === "requested"
      profileFollowsYou = snapshot.followsYou
    }

    setProfile(prof)
    setIsFollowing(following)
    setIsRequested(requested)
    setFollowsYou(profileFollowsYou)

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
      !isPrivateProfile || uid === prof.id || following

    if (canLoadTrades) {
      await fetchTrades(prof.id, true)
    } else {
      setTrades([])
      setPage(0)
      setHasMore(false)
    }

    setLoading(false)

    if (lookupByUuid && prof.username) {
      const target = profilePath(prof)
      const qs = searchParams.toString()
      router.replace(qs ? `${target}?${qs}` : target, { scroll: false })
    }
  }

  async function handleMessage() {
    if (!currentUserId || !profile || currentUserId === profile.id) return

    setMessageBusy(true)
    try {
      const result = await ensureDmConversation(
        supabase,
        currentUserId,
        profile.id,
        { skipGroupFilter: true }
      )

      if (!result.ok) {
        if (result.phase === "conversation") {
          logSupabaseError("handleMessage conversations insert", result.error, {
            table: "conversations",
            query: "insert",
            payload: { id: result.conversationId, is_group: false },
            userId: currentUserId,
            otherUserId: profile.id,
          })
        } else {
          logSupabaseError(
            "handleMessage conversation_participants insert",
            result.error,
            {
              table: "conversation_participants",
              query: "insert",
              payload: [
                { conversation_id: result.conversationId, user_id: currentUserId },
                { conversation_id: result.conversationId, user_id: profile.id },
              ],
              userId: currentUserId,
              conversationId: result.conversationId,
              otherUserId: profile.id,
            }
          )
        }
        return
      }

      router.push(dmThreadPath(profile))
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
      showPopup({ type: "warning", message: "Add some text or an image." })
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
        showPopup({ type: "error", message: upErr.message })
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
      showPopup({ type: "error", message: handleSupabaseError(error) })
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

  const emptyFollowSet = useMemo(() => new Set<string>(), [])

  const profileFollowingIds = useMemo(() => {
    if (!profile?.id || !isFollowing) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, isFollowing, emptyFollowSet])

  const profileRequestedIds = useMemo(() => {
    if (!profile?.id || !isRequested) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, isRequested, emptyFollowSet])

  const profileFollowsYouIds = useMemo(() => {
    if (!profile?.id || !followsYou) return emptyFollowSet
    return new Set([profile.id])
  }, [profile?.id, followsYou, emptyFollowSet])

  const handleProfileFollowingChange = useCallback(
    async (_targetId: string, following: boolean) => {
      setIsFollowing(following)
      if (!profile) return

      if (!following && profile.is_private === true) {
        setTrades([])
        setPage(0)
        setHasMore(false)
      } else if (following && profile.is_private === true) {
        setPage(0)
        setHasMore(true)
        await fetchTrades(profile.id, true)
      }

      const { count: followersN } = await supabase
        .from("followers")
        .select("*", { count: "exact", head: true })
        .eq("following_id", profile.id)

      setFollowersCount(followersN ?? 0)
    },
    [profile]
  )

  const handleProfileRequestedChange = useCallback(
    (_targetId: string, requested: boolean) => {
      setIsRequested(requested)
    },
    []
  )

  const canViewTrades =
    !!profile &&
    (profile.is_private !== true ||
      currentUserId === profile.id ||
      isFollowing)

  const clearProfileQueryParams = useCallback(() => {
    if (!profile) return
    router.replace(profilePath(profile), { scroll: false })
  }, [profile, router])

  const loadFeedPostEngagement = useCallback(
    async (postId: string, openComments = false) => {
      const [{ data: likesRows }, { data: commentsRows }] = await Promise.all([
        supabase.from("likes").select("post_id, user_id").eq("post_id", postId),
        supabase
          .from("comments")
          .select(FEED_COMMENTS_SELECT)
          .eq("post_id", postId)
          .order("created_at", { ascending: true }),
      ])

      let count = 0
      let liked = false
      for (const row of likesRows || []) {
        count += 1
        if (currentUserId && row.user_id === currentUserId) liked = true
      }

      setFeedDeepLinkLikeMeta({ count, liked })
      setFeedDeepLinkComments(commentsRows || [])
      if (openComments) {
        feedOpenCommentsRef.current[postId] = true
      }
    },
    [currentUserId]
  )

  const openFeedPostDeepLink = useCallback(
    async (postId: string, openComments = false) => {
      const { data: feedPost, error } = await supabase
        .from("posts")
        .select(FEED_POSTS_SELECT)
        .eq("id", postId)
        .maybeSingle()

      if (error || !feedPost) {
        clearProfileQueryParams()
        return
      }

      const tradeJoin = feedPost?.trades
      const tradeRow = tradeJoin
        ? Array.isArray(tradeJoin)
          ? tradeJoin[0]
          : tradeJoin
        : null
      const ownerId = tradeRow?.user_id ?? feedPost.user_id
      if (ownerId && profile?.id && String(ownerId) !== String(profile.id)) {
        clearProfileQueryParams()
        return
      }

      await loadFeedPostEngagement(postId, openComments)
      setFeedDeepLinkPost(feedPost)
      clearProfileQueryParams()
    },
    [clearProfileQueryParams, loadFeedPostEngagement, profile?.id]
  )

  const openTradeDeepLink = useCallback(
    async (tradeId: string) => {
      if (!profile?.id || !canViewTrades) {
        clearProfileQueryParams()
        return
      }

      setActiveTab("trades")

      let trade =
        trades.find((row) => String(row.id) === tradeId) ??
        allTrades.find((row) => String(row.id) === tradeId)

      if (!trade) {
        const { data, error } = await supabase
          .from("trades")
          .select("*")
          .eq("id", tradeId)
          .eq("user_id", profile.id)
          .eq("is_public", true)
          .maybeSingle()

        if (error || !data) {
          clearProfileQueryParams()
          return
        }
        trade = data
        setTrades((prev) =>
          prev.some((row) => String(row.id) === tradeId)
            ? prev
            : [data, ...prev]
        )
      }

      setSelectedTradeDetail({ ...trade, currentUserId })
      scrollToProfileTarget(`trade-${tradeId}`)
      clearProfileQueryParams()
    },
    [
      allTrades,
      canViewTrades,
      clearProfileQueryParams,
      currentUserId,
      profile?.id,
      trades,
    ]
  )

  const openProfilePostDeepLink = useCallback(
    (postId: string, focusComments = false) => {
      const wallPost = wallPosts.find((row) => String(row.id) === postId)
      if (!wallPost) return false

      setActiveTab("posts")
      setPostDetailFocusComments(focusComments)
      setSelectedPostDetail(wallPost)
      clearProfileQueryParams()
      return true
    },
    [clearProfileQueryParams, wallPosts]
  )

  useEffect(() => {
    if (!profile?.id || loading) return
    if (searchParams.get("post")?.trim() && !wallPostsReady) return

    const postParam = searchParams.get("post")?.trim()
    const tradeParam = searchParams.get("trade")?.trim()
    const openComments = searchParams.get("comments") === "1"
    const key = postParam
      ? `post:${postParam}:${openComments ? "1" : "0"}`
      : tradeParam
        ? `trade:${tradeParam}`
        : null

    if (!key || deepLinkHandledRef.current === key) return
    deepLinkHandledRef.current = key

    void (async () => {
      if (postParam) {
        if (!openProfilePostDeepLink(postParam, openComments)) {
          await openFeedPostDeepLink(postParam, openComments)
        }
        return
      }

      if (tradeParam) {
        await openTradeDeepLink(tradeParam)
      }
    })()
  }, [
    loading,
    openFeedPostDeepLink,
    openProfilePostDeepLink,
    openTradeDeepLink,
    profile?.id,
    searchParams,
    wallPostsReady,
  ])

  useEffect(() => {
    if (!profile?.id || !currentUserId || loading) return
    if (searchParams.get("followers") !== "1") return
    if (String(profile.id) !== String(currentUserId)) return

    void openFollowersModal()
    clearProfileQueryParams()
  }, [
    clearProfileQueryParams,
    currentUserId,
    loading,
    profile?.id,
    searchParams,
  ])

  const toggleFeedDeepLinkLike = useCallback(
    async (post: any) => {
      if (!currentUserId) return
      const pid = String(post.id)
      const meta = feedDeepLinkLikeMeta

      if (meta.liked) {
        const { error } = await supabase
          .from("likes")
          .delete()
          .eq("post_id", pid)
          .eq("user_id", currentUserId)
        if (error) return
        setFeedDeepLinkLikeMeta({
          count: Math.max(0, meta.count - 1),
          liked: false,
        })
        return
      }

      const { error } = await supabase
        .from("likes")
        .insert({ post_id: pid, user_id: currentUserId })
      if (error) return
      setFeedDeepLinkLikeMeta({ count: meta.count + 1, liked: true })
    },
    [currentUserId, feedDeepLinkLikeMeta]
  )

  const submitFeedDeepLinkComment = useCallback(
    async (post: any, text: string) => {
      if (!currentUserId) return false
      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false

      setFeedDeepLinkCommentSubmitting(true)
      const { data, error } = await supabase
        .from("comments")
        .insert({
          post_id: pid,
          user_id: currentUserId,
          content: trimmed,
        })
        .select(FEED_COMMENT_INSERT_SELECT)
        .single()
      setFeedDeepLinkCommentSubmitting(false)

      if (error) {
        console.error(error)
        return false
      }

      setFeedDeepLinkComments((prev) => [...prev, data])
      return true
    },
    [currentUserId]
  )

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

  // Public/profile analytics intentionally exclude backtest-mode trades.
  const analyticsTrades = filteredTrades.filter((trade) => {
    const modeStr = String(trade.mode ?? "").trim().toLowerCase()
    const typeStr = String(trade.account_type ?? "").trim().toLowerCase()
    return modeStr !== "backtest" && typeStr !== "backtest"
  })

  const profileOverviewTrades = allTrades.filter((trade) => {
    const modeStr = String(trade.mode ?? "").trim().toLowerCase()
    const typeStr = String(trade.account_type ?? "").trim().toLowerCase()
    return modeStr !== "backtest" && typeStr !== "backtest"
  })

  const statsVisible = canViewTrades

  const totalTrades = canViewTrades ? analyticsTrades.length : 0
  const wins = canViewTrades ? analyticsTrades.filter((t) => t.pnl > 0).length : 0
  const totalPnL = canViewTrades
    ? analyticsTrades.reduce((sum, t) => sum + (t.pnl || 0), 0)
    : 0

  const biggestWin = analyticsTrades.length
    ? Math.max(...analyticsTrades.map((t) => t.pnl || 0))
    : 0

  const biggestLoss = analyticsTrades.length
    ? Math.min(...analyticsTrades.map((t) => t.pnl || 0))
    : 0

  const longTrades = analyticsTrades.filter((t) => t.direction === "Long").length

  const equityData = analyticsTrades
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

  const overviewTotalTrades = statsVisible ? profileOverviewTrades.length : 0
  const overviewWins = statsVisible
    ? profileOverviewTrades.filter((t) => (Number(t.pnl) || 0) > 0).length
    : 0
  const overviewWinRate =
    statsVisible && overviewTotalTrades ? (overviewWins / overviewTotalTrades) * 100 : 0
  const overviewTotalPnL = statsVisible
    ? profileOverviewTrades.reduce((sum, t) => sum + (Number(t.pnl) || 0), 0)
    : 0
  const overviewAvgRR =
    statsVisible && overviewTotalTrades
      ? profileOverviewTrades.reduce((sum, t) => sum + (Number(t.rr) || 0), 0) /
        overviewTotalTrades
      : 0
  const overviewPayoutTotal = statsVisible
    ? achievements
        .filter((a) =>
          String(a.achievement_type ?? "").trim().toLowerCase().includes("payout")
        )
        .reduce((sum, a) => sum + (Number(a.value_numeric) || 0), 0)
    : 0
  const currentStreakLabel = (() => {
    if (!statsVisible || profileOverviewTrades.length === 0) return "—"
    const ordered = [...profileOverviewTrades].sort(
      (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )
    let streak = 0
    let sign: 1 | -1 | 0 = 0
    for (const trade of ordered) {
      const pnl = Number(trade.pnl) || 0
      const nextSign: 1 | -1 | 0 = pnl > 0 ? 1 : pnl < 0 ? -1 : 0
      if (nextSign === 0) {
        streak = 0
        sign = 0
        continue
      }
      if (nextSign === sign) {
        streak += 1
      } else {
        sign = nextSign
        streak = 1
      }
    }
    if (sign === 1 && streak > 0) return `W${streak}`
    if (sign === -1 && streak > 0) return `L${streak}`
    return "—"
  })()
  const grossWins = analyticsTrades.reduce((sum, t) => {
    const pnl = Number(t.pnl) || 0
    return pnl > 0 ? sum + pnl : sum
  }, 0)
  const grossLosses = analyticsTrades.reduce((sum, t) => {
    const pnl = Number(t.pnl) || 0
    return pnl < 0 ? sum + pnl : sum
  }, 0)
  const profitFactor =
    statsVisible && grossLosses < 0 ? grossWins / Math.abs(grossLosses) : null
  const avgWinner = wins > 0 ? grossWins / wins : null
  const lossCount = canViewTrades ? analyticsTrades.filter((t) => (Number(t.pnl) || 0) < 0).length : 0
  const avgLoser = lossCount > 0 ? grossLosses / lossCount : null
  const profitPerTrade = totalTrades > 0 ? totalPnL / totalTrades : null
  const { maxWinStreak, maxLossStreak } = (() => {
    const ordered = [...analyticsTrades].sort(
      (a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    )
    let currentWin = 0
    let currentLoss = 0
    let maxWin = 0
    let maxLoss = 0
    for (const trade of ordered) {
      const pnl = Number(trade.pnl) || 0
      if (pnl > 0) {
        currentWin += 1
        currentLoss = 0
      } else if (pnl < 0) {
        currentLoss += 1
        currentWin = 0
      } else {
        currentWin = 0
        currentLoss = 0
      }
      if (currentWin > maxWin) maxWin = currentWin
      if (currentLoss > maxLoss) maxLoss = currentLoss
    }
    return { maxWinStreak: maxWin, maxLossStreak: maxLoss }
  })()
  const sessionCounts = analyticsTrades.reduce<Record<string, number>>((acc, trade) => {
    const raw = String(trade.session ?? "").toLowerCase().trim()
    let label: "NY" | "London" | "Asia" | null = null
    if (raw.includes("ny") || raw.includes("new york")) label = "NY"
    else if (raw.includes("london") || raw.includes("ldn") || raw.includes("uk")) label = "London"
    else if (raw.includes("asia") || raw.includes("asian") || raw.includes("tokyo")) label = "Asia"
    if (!label) return acc
    acc[label] = (acc[label] || 0) + 1
    return acc
  }, {})
  const sessionTotal = Object.values(sessionCounts).reduce((sum, count) => sum + count, 0)
  const sessionBreakdown = (["NY", "London", "Asia"] as const)
    .map((label) => {
      const count = sessionCounts[label] || 0
      const pct = sessionTotal > 0 ? (count / sessionTotal) * 100 : 0
      return { label, count, pct }
    })
    .filter((row) => row.count > 0)

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
      <FeedbackModal {...feedbackModalProps} />
      {currentUserId === profile?.id ? (
        <StoryComposeModal
          open={storyComposeOpen}
          posting={postingStory}
          profile={
            profile
              ? {
                  id: currentUserId,
                  username: profile.username,
                  avatar_url: profile.avatar_url,
                }
              : null
          }
          previewUrl={pendingStoryPreviewUrl}
          onClose={closeStoryCompose}
          onPost={() => void handlePostStory()}
          onReplaceImage={(file) => void setStoryDraft(file)}
        />
      ) : null}

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
                    <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start sm:gap-3">
                      <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-start">
                        <h2 className="text-lg font-semibold text-white md:text-xl">
                          {profile.name || profile.username || "User"}
                        </h2>

                        {profile.username ? (
                          <>
                            <span className="text-gray-500">|</span>
                            <span className="text-sm text-gray-400">
                              {profile.username}
                            </span>
                          </>
                        ) : null}

                        {currentUserId === profile.id && (
                          <div className="flex items-center gap-2">
                            <button
                              type="button"
                              onClick={() => router.push("/settings#profile")}
                              className="rounded-md bg-gray-600 px-2 py-1 text-xs text-gray-100 hover:bg-gray-500 md:bg-white/10 md:px-3 md:text-sm md:hover:bg-white/20"
                            >
                              Settings
                            </button>
                          </div>
                        )}
                      </div>

                      {currentUserId && currentUserId !== profile.id && (
                        <div className="flex w-full flex-wrap items-center justify-center gap-2 sm:w-auto sm:justify-start">
                          <FollowButton
                            targetUserId={profile.id}
                            currentUserId={currentUserId}
                            targetIsPrivate={profile.is_private}
                            followingIds={profileFollowingIds}
                            requestedIds={profileRequestedIds}
                            followsYouIds={profileFollowsYouIds}
                            onFollowingChange={handleProfileFollowingChange}
                            onRequestedChange={handleProfileRequestedChange}
                            stopPropagation={false}
                          />

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

                    <p className="mt-1 flex flex-wrap items-center justify-center gap-1 text-sm text-gray-400 sm:justify-start">
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
                      <span aria-hidden="true">•</span>
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
                    </p>

                    <p className="mt-1 text-sm text-gray-400">
                      {formatProfileMetadataLine(profile)}
                    </p>

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
                    onChange={(e) => void handleStoryFileSelect(e)}
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

          <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6 md:gap-4">
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Trades</p>
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? overviewTotalTrades : "—"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Win %</p>
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? `${overviewWinRate.toFixed(1)}%` : "—"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Net P&amp;L</p>
              <p
                className={`text-lg font-semibold tabular-nums ${
                  !statsVisible
                    ? "text-white"
                    : overviewTotalPnL >= 0
                      ? "text-emerald-400"
                      : "text-red-400"
                }`}
              >
                {statsVisible ? formatMoney(overviewTotalPnL) : "—"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Payout Total</p>
              <p className="text-lg font-semibold tabular-nums text-emerald-400">
                {statsVisible ? formatMoney(overviewPayoutTotal) : "—"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Avg RR</p>
              <p className="text-lg font-semibold tabular-nums text-white">
                {statsVisible ? formatRR(overviewAvgRR) : "—"}
              </p>
            </div>
            <div className="rounded-xl border border-white/10 bg-white/5 p-4 text-center">
              <p className="text-xs text-gray-400">Streak</p>
              <p
                className={`text-lg font-semibold tabular-nums ${
                  currentStreakLabel.startsWith("W")
                    ? "text-emerald-400"
                    : currentStreakLabel.startsWith("L")
                      ? "text-red-400"
                      : "text-white"
                }`}
              >
                {currentStreakLabel}
              </p>
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
                    No public trades yet.
                  </p>
                ) : (
                  <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
                    {sortedTrades.map((trade) => (
                      <div key={trade.id} id={`trade-${trade.id}`}>
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
                        onOpenDetail={() => {
                          setTradeDetailFocusComments(false)
                          setSelectedTradeDetail({ ...trade, currentUserId })
                        }}
                        onOpenComments={() => {
                          setTradeDetailFocusComments(true)
                          setSelectedTradeDetail({ ...trade, currentUserId })
                        }}
                      />
                      </div>
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
                        <div key={post.id} id={`post-${key}`}>
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
                          onOpenComments={() => {
                            setPostDetailFocusComments(true)
                            setSelectedPostDetail(post)
                          }}
                          onOpenDetail={() => {
                            setPostDetailFocusComments(false)
                            setSelectedPostDetail(post)
                          }}
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
                        </div>
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
                      <Stat
                        title="Profit Factor"
                        value={
                          statsVisible
                            ? profitFactor == null
                              ? "—"
                              : profitFactor.toLocaleString(undefined, {
                                  minimumFractionDigits: 0,
                                  maximumFractionDigits: 2,
                                })
                            : "—"
                        }
                        positive={profitFactor != null ? profitFactor >= 1 : undefined}
                      />
                      <Stat
                        title="Avg Winner"
                        value={statsVisible && avgWinner != null ? formatCurrency(avgWinner) : "—"}
                        positive
                      />
                      <Stat
                        title="Avg Loser"
                        value={statsVisible && avgLoser != null ? formatCurrency(avgLoser) : "—"}
                        positive={false}
                      />
                      <Stat
                        title="Profit / Trade"
                        value={statsVisible && profitPerTrade != null ? formatCurrency(profitPerTrade) : "—"}
                        positive={profitPerTrade != null ? profitPerTrade >= 0 : undefined}
                      />
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
                        <p className="font-semibold tabular-nums">{longTrades}</p>
                      </div>

                      <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                        <p className="text-sm text-gray-400">Largest Streaks</p>
                        <p className="font-semibold tabular-nums">
                          W{maxWinStreak} / L{maxLossStreak}
                        </p>
                      </div>
                    </div>

                    <div className="rounded-xl border border-white/10 bg-white/5 p-4 md:p-5">
                      <div className="mb-3 flex items-center justify-between">
                        <h3 className="text-base font-semibold text-white">Trading Sessions</h3>
                        <p className="text-xs text-gray-400">
                          {sessionTotal > 0 ? `${sessionTotal} trades tagged` : "No session data"}
                        </p>
                      </div>
                      {sessionBreakdown.length === 0 ? (
                        <p className="text-sm text-gray-400">
                          Add session tags to trades to unlock this breakdown.
                        </p>
                      ) : (
                        <div className="space-y-2.5">
                          {sessionBreakdown.map((row) => (
                            <div key={row.label} className="space-y-1">
                              <div className="flex items-center justify-between text-sm">
                                <span className="font-medium text-gray-200">{row.label}</span>
                                <span className="tabular-nums text-gray-300">
                                  {row.pct.toFixed(0)}%
                                </span>
                              </div>
                              <div className="h-2 overflow-hidden rounded-full bg-white/10">
                                <div
                                  className="h-full rounded-full bg-gradient-to-r from-blue-500 to-emerald-400"
                                  style={{ width: `${Math.max(4, Math.round(row.pct))}%` }}
                                />
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
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

              {postImagePreviewUrl ? (
                <div className="mb-3 flex flex-col items-center">
                  <img
                    src={postImagePreviewUrl}
                    alt="Selected image preview"
                    className="max-h-48 w-full rounded-xl border border-white/10 bg-black/30 object-contain"
                  />
                  {postImage ? (
                    <p className="mt-1.5 text-xs text-gray-500">
                      {formatPostFileSize(postImage.size)}
                    </p>
                  ) : null}
                </div>
              ) : null}

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
        <DetailModalShell
          ariaLabel="Trade details"
          title="Trade"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedTradeDetail(null)
            setTradeDetailFocusComments(false)
          }}
        >
          <TradeCard
            inDetailModal
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
            commentsExpanded
            scrollToCommentsOnMount={tradeDetailFocusComments}
            disableOpen
          />
        </DetailModalShell>
      ) : null}

      {selectedPostDetail ? (
        <DetailModalShell
          ariaLabel="Post details"
          title="Post"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedPostDetail(null)
            setPostDetailFocusComments(false)
          }}
        >
          <PostCard
            inDetailModal
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
            showCommentsPanel
            scrollToCommentsOnMount={postDetailFocusComments}
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
        </DetailModalShell>
      ) : null}

      {feedDeepLinkPost ? (
        <FeedPostDetailModal
          post={feedDeepLinkPost}
          user={currentUserId ? { id: currentUserId } : null}
          comments={feedDeepLinkComments}
          likeMeta={feedDeepLinkLikeMeta}
          commentSubmitting={feedDeepLinkCommentSubmitting}
          draftSyncRef={feedDraftSyncRef}
          openCommentsRef={feedOpenCommentsRef}
          onClose={() => setFeedDeepLinkPost(null)}
          onToggleLike={toggleFeedDeepLinkLike}
          onSubmitComment={submitFeedDeepLinkComment}
          onSharePost={() => {}}
        />
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
                      router.push(profilePath(u))
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
                      router.push(profilePath(u))
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

export default function ProfilePage() {
  return (
    <Suspense
      fallback={
        <>
          <Navbar />
          <div className="flex min-h-[50vh] items-center justify-center text-sm text-gray-400">
            Loading profile…
          </div>
        </>
      }
    >
      <ProfilePageContent />
    </Suspense>
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
