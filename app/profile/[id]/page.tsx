"use client"

import Link from "next/link"
import Navbar from "../../components/Navbar"
import EmptyState from "../../components/ui/EmptyState"
import { SkeletonProfilePage } from "../../components/ui/skeletons"
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
import { deleteUserTrade } from "@/lib/deleteTrade"
import { compressImage } from "@/lib/compressImage"
import { normalizeTraderType } from "@/lib/traderType"
import { useParams, useRouter, useSearchParams } from "next/navigation"
import FeedPostDetailModal from "../../components/feed/FeedPostDetailModal"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "../../components/ui/DetailModalShell"
import DropdownMenu from "@/app/components/ui/DropdownMenu"
import DetailModalImage from "../../components/ui/DetailModalImage"
import ImageLightbox from "../../components/ui/ImageLightbox"
import { EMPTY_LIKE_META } from "../../components/feed/FeedPostCard"
import FeedCommentItem from "../../components/feed/FeedCommentItem"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import {
  buildReplyTargetFromComment,
  indexCommentsById,
  resolveParentComment,
  type ReplyTarget,
} from "@/lib/replyReference"
import EngagementCountButton from "../../components/EngagementCountButton"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import {
  FEED_COMMENT_INSERT_SELECT,
  FEED_POSTS_SELECT,
  postTradeOwnerUserId,
  queryFeedComments,
  withInsertedParentCommentId,
} from "../../components/feed/feedPostHelpers"
import FeedRoomShareCard from "../../components/feed/FeedRoomShareCard"
import {
  buildRoomSharePostInsert,
  isRoomSharePost,
  pendingRoomShareFromRoom,
  type PendingRoomShareDraft,
} from "@/lib/roomSharePost"
import {
  deleteFeedComment,
  deleteProfilePostComment,
  deleteTradeComment,
  filterCommentsAfterDelete,
} from "@/lib/deleteComment"
import {
  deleteLikeNotification,
  ensureLikeNotification,
} from "@/lib/likeNotifications"
import { ensureCommentNotificationsForInsert } from "@/lib/commentNotifications"
import {
  PROFILE_POST_COMMENT_INSERT_SELECT,
  insertProfilePostCommentNotifications,
  profilePostOwnerUserId,
  queryProfilePostComments,
  withInsertedProfilePostParentCommentId,
} from "@/lib/profilePostEngagement"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
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
import ShareToConversationsModal from "../../components/ShareToConversationsModal"
import InputTradeForm from "../../components/InputTradeForm"
import Calendar from "../../components/Calendar"
import {
  type Achievement,
  fetchOwnAchievements,
  fetchVisibleProfileAchievements,
  formatAchievementDate,
  sumPayoutAchievementTotals,
} from "../../../lib/achievements"
import { formatPnlCurrency } from "../../../lib/formatMoney"
import { formatRR, formatTradePoints } from "@/lib/formatDisplay"
import { averageRrFromTrades } from "@/lib/tradeRr"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import TradeCardTimingBlock from "../../components/TradeCardTimingBlock"
import { formatRelativeTime } from "@/lib/formatRelativeTime"
import { createUserRoom } from "@/lib/createUserRoom"
import { loadFollowUiSnapshot } from "@/lib/followActions"
import FollowButton from "../../components/FollowButton"
import { logSupabaseError } from "@/lib/logSupabaseError"
import { ensureDmConversation } from "@/lib/dmConversation"
import { dmThreadPath } from "@/lib/messageRoutes"
import { ConfirmModal, FeedbackModal, useDeleteTradeConfirmation, useFeedbackPopup } from "@/app/components/ui"
import StoryComposeModal from "../../components/feed/StoryComposeModal"
import { publishStory } from "@/lib/publishStory"
import {
  createStoryPreviewUrl,
  prepareStoryImageFile,
  revokeStoryPreviewUrl,
} from "@/lib/storyComposeHelpers"
import { isProfileUuidSegment, profilePath } from "@/lib/profileRoutes"
import {
  ProfileAvatarLink,
  ProfileLink,
  ProfileUsernameLink,
} from "@/app/components/ProfileLink"
import { normalizeProfileUsername } from "@/lib/profileUsername"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { notifyGettingStartedChecklistMaybeCompleted } from "@/lib/gettingStartedProgressSync"
import {
  formatPublicAccountTypeLabel,
  PUBLIC_TRADE_SELECT,
  sanitizeTradeForViewer,
  sanitizeTradesForViewer,
  tradeSelectForViewer,
} from "@/lib/publicAccountPrivacy"

/** Public profile columns only — never fetch billing, referral, or moderation fields here. */
const PUBLIC_PROFILE_SELECT =
  "id, username, name, bio, avatar_url, trading_style, trader_type, primary_market, started_trading, is_private, created_at" as const

const PRIVATE_PROFILE_TAB_COPY = {
  trades: "This trader has chosen to keep their trades private.",
  posts: "Posts are only visible to approved followers.",
} as const

function PrivateProfileTabMessage({
  variant,
}: {
  variant: keyof typeof PRIVATE_PROFILE_TAB_COPY
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
      <p className="text-lg text-gray-100">🔒 Private Profile</p>
      <p className="mt-2 text-sm text-gray-400">
        {PRIVATE_PROFILE_TAB_COPY[variant]}
      </p>
      <p className="mt-2 text-sm text-gray-400">
        Follow this trader to request access.
      </p>
    </div>
  )
}

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
  onStartEditTrade,
  onTogglePinTrade,
  onDeleteTrade,
  showInteractions,
  onOpenDetail,
  onOpenComments,
  commentsExpanded = false,
  scrollToCommentsOnMount = false,
  inDetailModal = false,
  disableOpen,
  onImageClick,
}: {
  trade: any
  profile: any
  /** Logged-in viewer profile (referral_code for share PNG) */
  shareProfile?: { referral_code?: string | null } | null
  canManageTrade?: boolean
  onStartEditTrade?: () => void
  onTogglePinTrade?: () => void
  onDeleteTrade?: () => void
  showInteractions?: boolean
  onOpenDetail?: () => void
  onOpenComments?: () => void
  commentsExpanded?: boolean
  scrollToCommentsOnMount?: boolean
  inDetailModal?: boolean
  disableOpen?: boolean
  onImageClick?: (url: string) => void
}) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    Boolean(scrollToCommentsOnMount)
  )
  const imageSrc = postImageSrc(trade.image_url)
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const direction = trade.direction ?? "—"
  const ticker = trade.ticker ?? "—"
  const accountTypeNorm = String(trade.account_type ?? "").trim().toLowerCase()
  const rr =
    trade.rr != null && trade.rr !== "" ? formatRR(trade.rr) : "—"
  const resolvedPoints = resolveTradePoints(trade)
  const pointsLabel =
    resolvedPoints !== null ? formatTradePoints(trade) : null
  const pnlLabel = Number.isFinite(pnl)
    ? `${pnl >= 0 ? "+" : ""}${formatMoney(pnl)}`
    : "—"
  const desc = trade.public_description
    ? String(trade.public_description).trim()
    : ""

  useEffect(() => {
    if (scrollToCommentsOnMount) setCommentsFocused(true)
  }, [scrollToCommentsOnMount, trade.id])

  const tradeCompactMeta = (
    <>
      <span
        className={
          Number.isFinite(pnl)
            ? pnl >= 0
              ? "text-emerald-400"
              : "text-red-400"
            : "text-gray-400"
        }
      >
        {pnlLabel}
      </span>
      <span className="text-gray-500"> · </span>
      <span>
        {ticker} · {direction}
      </span>
    </>
  )

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

          {trade.id ? (
            <Link
              href={`/trade/${trade.id}`}
              className="min-w-0 truncate font-medium text-white hover:text-blue-200"
              onClick={(e) => e.stopPropagation()}
            >
              {ticker} · {direction}
            </Link>
          ) : (
            <span className="min-w-0 truncate font-medium text-white">
              {ticker} · {direction}
            </span>
          )}

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
              {formatPublicAccountTypeLabel(accountTypeNorm) ?? accountTypeNorm.toUpperCase()}
            </span>
          ) : null}
        </div>
        <div className="flex shrink-0 items-center gap-3 text-gray-300 tabular-nums">
          <span>RR {rr}</span>
          {pointsLabel ? <span>Pts {pointsLabel}</span> : null}
        </div>
      </div>
      {desc ? (
        <p className="px-1 text-sm leading-relaxed text-white">{desc}</p>
      ) : null}
      <TradeCardTimingBlock trade={trade} />
    </>
  )

  const cardShellClass = inDetailModal
    ? "flex min-h-0 flex-1 flex-col overflow-hidden bg-transparent md:flex-row"
    : `h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`

  const tradeAuthorHeader = (
    <div className="flex shrink-0 items-center justify-between border-b border-white/5 px-4 py-3">
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
          <div onClick={(e) => e.stopPropagation()}>
            <DropdownMenu
              stopPropagation
              menuClassName="z-[9100]"
              trigger={
                <span className="px-1 text-gray-400 hover:text-white">•••</span>
              }
              items={[
                {
                  id: "edit",
                  label: "Edit Trade",
                  onSelect: () => onStartEditTrade?.(),
                },
                {
                  id: "pin",
                  label: trade.is_pinned ? "Unpin Trade" : "Pin Trade",
                  onSelect: () => onTogglePinTrade?.(),
                },
                {
                  id: "delete",
                  label: "Delete Trade",
                  variant: "danger",
                  onSelect: () => onDeleteTrade?.(),
                },
              ]}
            />
          </div>
        ) : null}
      </div>
    </div>
  )

  const tradeImageBlock = imageSrc ? (
    <DetailModalImage src={imageSrc} onClick={onImageClick} />
  ) : (
    <div className="flex min-h-[80px] w-full items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] text-xs text-gray-500">
      No screenshot
    </div>
  )

  if (inDetailModal) {
    return (
      <article className={cardShellClass}>
        {imageSrc ? (
          <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:bg-black/40 md:p-3">
            {tradeImageBlock}
          </div>
        ) : null}

        <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:w-[400px] md:shrink-0 lg:w-[420px]">
          {showInteractions ? (
            <TradeSocialProvider
              tradeId={trade.id}
              currentUserId={trade.currentUserId}
              tradeOwnerUserId={trade.user_id}
              commentsExpanded={commentsExpanded}
              onRequestComments={commentsExpanded ? undefined : onOpenComments}
              scrollToCommentsOnMount={scrollToCommentsOnMount}
              enableRealtime
            >
              <MobileCommentFocusLayout
                commentsFocused={commentsFocused}
                header={tradeAuthorHeader}
                compactHeader={
                  <CommentFocusCompactStrip
                    userId={String(profile.id ?? "")}
                    username={profile.username}
                    avatarUrl={profile.avatar_url}
                    timestamp={trade.created_at ?? trade.trade_date}
                    meta={tradeCompactMeta}
                    onExpand={() => setCommentsFocused(false)}
                  />
                }
                mobileMedia={imageSrc ? tradeImageBlock : undefined}
                engagement={
                  <TradeSocialEngagementBar
                    onCommentsFocus={() => setCommentsFocused(true)}
                  />
                }
                engagementClassName="shrink-0 border-t border-white/10 px-4 py-2 md:border-t-0"
                collapsibleContent={
                  <div className="space-y-3 px-4 pb-3 pt-4">{tradeDetails}</div>
                }
                comments={
                  commentsExpanded ? (
                    <TradeSocialCommentsSection
                      className="px-4 pb-4"
                      scrollContainerRef={commentsScrollRef}
                    />
                  ) : null
                }
              />
            </TradeSocialProvider>
          ) : (
            <>
              {tradeAuthorHeader}
              {imageSrc ? (
                <div className="shrink-0 bg-black/30 md:hidden">{tradeImageBlock}</div>
              ) : null}
              <div className="space-y-3 p-4">{tradeDetails}</div>
            </>
          )}
        </div>
      </article>
    )
  }

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
      {tradeAuthorHeader}

      {imageSrc ? (
        <div className="relative w-full bg-black/30">
          <img
            src={imageSrc}
            alt=""
            loading="lazy"
            decoding="async"
            className="block w-full max-h-[400px] object-cover"
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
            commentsExpanded={commentsExpanded}
            onRequestComments={commentsExpanded ? undefined : onOpenComments}
            scrollToCommentsOnMount={scrollToCommentsOnMount}
          >
            <div className="border-t border-white/10 px-4 py-2">
              <TradeSocialEngagementBar />
            </div>
            <div className="space-y-3 px-4 pb-3">{tradeDetails}</div>
            {commentsExpanded ? (
              <TradeSocialCommentsSection className="px-4 pb-4" />
            ) : null}
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
  likeBusy = false,
  onOpenComments,
  showCommentsPanel,
  scrollToCommentsOnMount,
  likeMeta,
  comments,
  commentText,
  onCommentChange,
  onCommentSubmit,
  commentSubmitting,
  currentUserId,
  onDeleteComment,
  onOpenDetail,
  inDetailModal = false,
  disableOpen,
  onImageClick,
  onSharePost,
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
  likeBusy?: boolean
  onOpenComments?: () => void
  showCommentsPanel?: boolean
  scrollToCommentsOnMount?: boolean
  likeMeta?: { count: number; liked: boolean }
  comments?: any[]
  commentText?: string
  onCommentChange?: (value: string) => void
  onCommentSubmit?: (parentCommentId?: string | null) => void
  commentSubmitting?: boolean
  currentUserId?: string | null
  onDeleteComment?: (comment: any) => Promise<boolean>
  onOpenDetail?: () => void
  inDetailModal?: boolean
  disableOpen?: boolean
  onImageClick?: (url: string) => void
  onSharePost?: (post: any) => void
}) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [replyTarget, setReplyTarget] = useState<ReplyTarget | null>(null)
  const [pendingDelete, setPendingDelete] = useState<any>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [commentsFocused, setCommentsFocused] = useState(
    Boolean(scrollToCommentsOnMount && showCommentsPanel)
  )
  const imgSrc = profileWallImageSrc(post.image_url)
  const postCommentInputId = `profile-comment-input-${post.id}`

  useEffect(() => {
    if (scrollToCommentsOnMount && showCommentsPanel) setCommentsFocused(true)
  }, [scrollToCommentsOnMount, showCommentsPanel, post.id])

  useEffect(() => {
    setReplyTarget(null)
  }, [post.id])

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

  const commentsById = useMemo(
    () => indexCommentsById(comments || []),
    [comments]
  )

  const commentsList = (
    <div className="space-y-2 text-sm text-gray-300">
      {(comments || []).map((c: any) => (
        <FeedCommentItem
          key={c.id}
          comment={c}
          parentComment={resolveParentComment(c, commentsById)}
          currentUserId={currentUserId}
          onReply={(comment) => {
            setReplyTarget(buildReplyTargetFromComment(comment))
            const input = document.getElementById(postCommentInputId)
            if (input instanceof HTMLInputElement) input.focus()
          }}
          onRequestDelete={
            onDeleteComment
              ? (comment) =>
                  setPendingDelete({
                    ...comment,
                    post_id: comment.post_id ?? post.id,
                  })
              : undefined
          }
          deleteMenuClassName="z-[9100]"
        />
      ))}
    </div>
  )

  const commentsComposer = (
    <div className="flex flex-col gap-2">
      {replyTarget ? (
        <ReplyComposerStrip
          authorName={replyTarget.authorName}
          preview={replyTarget.preview}
          onCancel={() => setReplyTarget(null)}
        />
      ) : null}
      <div className="flex gap-2">
      <input
        id={postCommentInputId}
        value={commentText || ""}
        onChange={(e) => onCommentChange?.(e.target.value)}
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.shiftKey) {
            e.preventDefault()
            if (!commentSubmitting) {
              onCommentSubmit?.(replyTarget?.id ?? null)
              setReplyTarget(null)
            }
          }
        }}
        placeholder={replyTarget ? "Write a reply…" : "Add a comment..."}
        className="flex-1 rounded-lg border border-white/10 bg-[#0f172a] px-3 py-2 text-sm text-white placeholder:text-gray-500"
      />
      <button
        type="button"
        onClick={(e) => {
          e.stopPropagation()
          onCommentSubmit?.(replyTarget?.id ?? null)
          setReplyTarget(null)
        }}
        disabled={commentSubmitting || !(commentText || "").trim()}
        className="rounded-lg bg-blue-500 px-3 py-2 text-sm text-white disabled:opacity-40"
      >
        Post
      </button>
      </div>
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
    ? "flex min-h-0 flex-1 flex-col overflow-hidden bg-transparent md:flex-row"
    : `h-fit w-full overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20 ${
        onOpenDetail && !disableOpen
          ? "cursor-pointer transition-all duration-200 hover:border-white/20 hover:bg-white/[0.07] hover:shadow-xl"
          : ""
      }`

  const postAuthorHeader = (
    <div className="flex shrink-0 items-center justify-between gap-3 border-b border-white/5 p-4">
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
  )

  const postImageBlock =
    imgSrc != null ? (
      <DetailModalImage src={imgSrc} onClick={onImageClick} />
    ) : null

  const postEngagementRow = showInteractions ? (
    <div className="flex items-center gap-4 px-1 text-sm">
      <EngagementCountButton
        icon={<span>{likeMeta?.liked ? "❤️" : "🤍"}</span>}
        count={likeMeta?.count ?? 0}
        ariaLabel={likeMeta?.liked ? "Unlike" : "Like"}
        disabled={likeBusy}
        onClick={(e) => {
          e.stopPropagation()
          onLike?.()
        }}
        className="text-gray-300 hover:text-white"
        countClassName="tabular-nums"
      />
      <EngagementCountButton
        icon={<span>💬</span>}
        count={comments?.length ?? 0}
        ariaLabel="View comments"
        onClick={(e) => {
          e.stopPropagation()
          setCommentsFocused(true)
          onOpenComments?.()
          if (inDetailModal && showCommentsPanel) {
            requestAnimationFrame(() => {
              scrollModalCommentsPane(commentsScrollRef.current)
            })
          }
        }}
        className="text-gray-300 hover:text-white"
        countClassName="tabular-nums"
      />
      {onSharePost ? (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation()
            onSharePost(post)
          }}
          className="flex h-9 w-9 items-center justify-center rounded-lg bg-white/5 text-gray-300 transition hover:bg-white/10 hover:text-white"
          aria-label="Share post"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            className="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
            />
          </svg>
        </button>
      ) : null}
    </div>
  ) : null

  const postContentBlock = (
    <div className="shrink-0 space-y-3 p-4">
      {post.content ? (
        <p className="px-1 text-sm leading-relaxed text-white">{post.content}</p>
      ) : null}
      <p className="text-xs text-gray-400">{formatRelativeTime(post.created_at, Date.now(), "compact")}</p>
      {showInteractions ? (
        <div className="border-t border-white/10 pt-3">
          {postEngagementRow}
          <p className="px-1 pt-2 text-sm font-medium text-white">
            {(likeMeta?.count ?? 0).toLocaleString()} likes
          </p>
          {!inDetailModal ? commentsPanel : null}
        </div>
      ) : null}
    </div>
  )

  const postCollapsibleContent = (
    <div className="shrink-0 space-y-3 p-4">
      {post.content ? (
        <p className="px-1 text-sm leading-relaxed text-white">{post.content}</p>
      ) : null}
      <p className="text-xs text-gray-400">{formatRelativeTime(post.created_at, Date.now(), "compact")}</p>
      <p className="px-1 text-sm font-medium text-white">
        {(likeMeta?.count ?? 0).toLocaleString()} likes
      </p>
    </div>
  )

  const deleteModal = onDeleteComment ? (
    <ConfirmModal
      open={pendingDelete != null}
      title="Delete Comment?"
      description="This action cannot be undone."
      confirmLabel="Delete"
      destructive
      loading={deleteBusy}
      onCancel={() => {
        if (!deleteBusy) setPendingDelete(null)
      }}
      onConfirm={async () => {
        if (!pendingDelete || !onDeleteComment) return
        console.log("[comment-delete] confirm", {
          commentId: String(pendingDelete.id),
          postId: pendingDelete.post_id ?? post.id,
        })
        setDeleteBusy(true)
        try {
          const ok = await onDeleteComment({
            ...pendingDelete,
            post_id: pendingDelete.post_id ?? post.id,
          })
          console.log("[comment-delete] handler finished", {
            commentId: String(pendingDelete.id),
            ok,
          })
          if (ok) setPendingDelete(null)
        } finally {
          setDeleteBusy(false)
        }
      }}
    />
  ) : null

  if (inDetailModal) {
    const postCommentsPanel = showCommentsPanel ? (
      <div
        id={`profile-post-comments-${post.id}`}
        className="flex min-h-0 flex-1 flex-col overflow-hidden"
      >
        <div
          ref={commentsScrollRef}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-4 pt-3"
        >
          {commentsList}
        </div>
        <div className="shrink-0 px-4 pb-4 pt-3">{commentsComposer}</div>
      </div>
    ) : null

    return (
      <>
        <article className={cardShellClass}>
          {isRoomSharePost(post) ? (
            <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:bg-black/40 md:p-3">
              <FeedRoomShareCard
                post={post}
                viewerUserId={currentUserId ?? null}
                className="w-full max-w-md"
              />
            </div>
          ) : imgSrc ? (
            <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:bg-black/40 md:p-3">
              {postImageBlock}
            </div>
          ) : null}

          <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:w-[400px] md:shrink-0 lg:w-[420px]">
            <MobileCommentFocusLayout
              commentsFocused={commentsFocused}
              header={postAuthorHeader}
              compactHeader={
                <CommentFocusCompactStrip
                  userId={String(profile.id ?? "")}
                  username={profile.username}
                  avatarUrl={profile.avatar_url}
                  timestamp={post.created_at}
                  onExpand={() => setCommentsFocused(false)}
                />
              }
              mobileMedia={
                isRoomSharePost(post) ? (
                  <FeedRoomShareCard
                    post={post}
                    viewerUserId={currentUserId ?? null}
                    className="mx-4 my-3"
                  />
                ) : (
                  postImageBlock ?? undefined
                )
              }
              engagement={postEngagementRow}
              engagementClassName="shrink-0 border-b border-white/10 px-4 py-2"
              collapsibleContent={postCollapsibleContent}
              comments={postCommentsPanel}
            />
          </div>
        </article>
        {deleteModal}
      </>
    )
  }

  return (
    <>
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
      {postAuthorHeader}

      {isRoomSharePost(post) ? (
        <div className="p-4" onClick={(e) => e.stopPropagation()}>
          <FeedRoomShareCard
            post={post}
            viewerUserId={currentUserId ?? null}
          />
        </div>
      ) : imgSrc ? (
        <div className="w-full bg-black/30">
          <img
            src={imgSrc}
            alt=""
            loading="lazy"
            decoding="async"
            className="block w-full max-h-[400px] object-cover"
            onError={(e) => {
              e.currentTarget.style.display = "none"
            }}
          />
        </div>
      ) : null}

      {postContentBlock}
    </article>
      {deleteModal}
    </>
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

/** Append rows without duplicate ids (pagination races, deep links). */
function mergeUniqueById<T extends { id: string | number }>(
  existing: T[],
  incoming: T[]
): T[] {
  if (!incoming.length) return existing
  const seen = new Set(existing.map((row) => String(row.id)))
  const merged = [...existing]
  for (const row of incoming) {
    const id = String(row.id)
    if (seen.has(id)) continue
    seen.add(id)
    merged.push(row)
  }
  return merged
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
  const [allTrades, setAllTrades] = useState<any[]>([])
  const [visibleTradeCount, setVisibleTradeCount] = useState(PAGE_SIZE)
  const [loading, setLoading] = useState(true)
  /** Set when profile row fails to load (wrong env, RLS, missing row, or network). */
  const [lastProfileFetchError, setLastProfileFetchError] = useState<string | null>(
    null
  )
  const [followersCount, setFollowersCount] = useState(0)
  const [followingCount, setFollowingCount] = useState(0)
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const { profile: viewerContextProfile } = useUserProfile()
  const viewerShareProfile =
    viewerContextProfile?.referral_code != null
      ? { referral_code: viewerContextProfile.referral_code }
      : null
  const [isFollowing, setIsFollowing] = useState(false)
  const [isRequested, setIsRequested] = useState(false)
  const [followsYou, setFollowsYou] = useState(false)

  const canViewTrades = useMemo(
    () =>
      !!profile &&
      (profile.is_private !== true ||
        currentUserId === profile.id ||
        isFollowing),
    [profile, currentUserId, isFollowing]
  )
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
  const [pendingRoomShare, setPendingRoomShare] =
    useState<PendingRoomShareDraft | null>(null)
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
  const [editingPost, setEditingPost] = useState<any | null>(null)
  const [editContent, setEditContent] = useState("")
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [selectedMode, setSelectedMode] = useState("all")
  const [achievements, setAchievements] = useState<Achievement[]>([])
  const [selectedTradeDetail, setSelectedTradeDetail] = useState<any | null>(null)
  const [selectedPostDetail, setSelectedPostDetail] = useState<any | null>(null)
  const [screenshotLightboxUrl, setScreenshotLightboxUrl] = useState<string | null>(
    null
  )
  const [selectedAchievementImage, setSelectedAchievementImage] = useState<{
    src: string
    title: string
    achievedAt: string | null
    description: string | null
  } | null>(null)
  const [feedDeepLinkPost, setFeedDeepLinkPost] = useState<any | null>(null)
  const [sharePost, setSharePost] = useState<any | null>(null)
  const [feedDeepLinkLikeMeta, setFeedDeepLinkLikeMeta] = useState(EMPTY_LIKE_META)
  const [feedDeepLinkComments, setFeedDeepLinkComments] = useState<any[]>([])
  const [feedDeepLinkCommentSubmitting, setFeedDeepLinkCommentSubmitting] =
    useState(false)
  const feedDraftSyncRef = useRef<Record<string, string>>({})
  const feedOpenCommentsRef = useRef<Record<string, boolean>>({})
  const creatingRoomRef = useRef(false)
  const creatingPostRef = useRef(false)
  const postingStoryRef = useRef(false)
  const likeBusyRef = useRef<Set<string>>(new Set())
  const commentSubmittingRef = useRef<Set<string>>(new Set())
  const feedDeepLinkLikeBusyRef = useRef(false)
  const feedDeepLinkCommentSubmittingRef = useRef(false)
  const [likeBusyByPost, setLikeBusyByPost] = useState<Record<string, boolean>>({})
  const deepLinkHandledRef = useRef<string | null>(null)

  const openCreatePostModal = useCallback(() => {
    setShowCreatePost(true)
  }, [])

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
    if (!pendingStoryFile || !currentUserId || postingStoryRef.current || postingStory) {
      return
    }
    postingStoryRef.current = true
    setPostingStory(true)

    try {
      const result = await publishStory(supabase, currentUserId, pendingStoryFile)

      if (!result.ok) {
        showPopup({ type: "error", message: result.message })
        return
      }

      showPopup({ type: "success", message: "Story uploaded!" })
      closeStoryCompose()
      await loadFollowingStories()
    } finally {
      postingStoryRef.current = false
      setPostingStory(false)
    }
  }, [
    pendingStoryFile,
    currentUserId,
    postingStory,
    showPopup,
    closeStoryCompose,
    loadFollowingStories,
  ])

  const fetchTradesForProfile = useCallback(
    async (forProfileId: string) => {
      const isOwner =
        currentUserId != null && String(currentUserId) === String(forProfileId)

      const { data, error } = await supabase
        .from("trades")
        .select(tradeSelectForViewer(isOwner))
        .eq("user_id", forProfileId)
        .eq("is_public", true)

      if (error) {
        console.error("all trades fetch:", error)
        return []
      }

      return sanitizeTradesForViewer(data || [], { isOwner })
    },
    [currentUserId]
  )

  const publicTradesByDate = useMemo(
    () =>
      allTrades
        .filter((trade) => trade.is_public === true)
        .sort(
          (a, b) =>
            new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
        ),
    [allTrades]
  )

  const trades = useMemo(
    () => publicTradesByDate.slice(0, visibleTradeCount),
    [publicTradesByDate, visibleTradeCount]
  )

  const hasMore = visibleTradeCount < publicTradesByDate.length

  useEffect(() => {
    if (!profileId) {
      setProfile(null)
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
      setLoading(false)
      return
    }

    console.log("ProfileId from URL:", profileId)

    setProfile(null)
    setAllTrades([])
    setVisibleTradeCount(PAGE_SIZE)
    setWallPosts([])
    setLoading(true)

    fetchProfile(profileId)
    deepLinkHandledRef.current = null
  }, [profileId])

  useEffect(() => {
    if (!profile?.id || !canViewTrades) {
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
      return
    }

    let cancelled = false

    void (async () => {
      const rows = await fetchTradesForProfile(profile.id)
      if (!cancelled) setAllTrades(rows)
    })()

    return () => {
      cancelled = true
    }
  }, [profile?.id, canViewTrades, fetchTradesForProfile])

  useEffect(() => {
    setVisibleTradeCount(PAGE_SIZE)
  }, [profile?.id])

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
    if (!profile?.id) {
      setAchievements([])
      return
    }
    let cancelled = false
    async function fetchProfileAchievements() {
      const isOwner =
        currentUserId != null && String(currentUserId) === String(profile.id)
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
    if (
      showCreatePost ||
      editingPost ||
      selectedAchievementImage ||
      selectedTradeDetail ||
      selectedPostDetail ||
      feedDeepLinkPost ||
      sharePost
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
    sharePost,
  ])

  useEffect(() => {
    if (
      !showCreatePost &&
      !editingPost &&
      !selectedAchievementImage &&
      !selectedTradeDetail &&
      !selectedPostDetail &&
      !feedDeepLinkPost &&
      !sharePost
    )
      return
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setShowCreatePost(false)
        setPendingRoomShare(null)
        setEditingPost(null)
        setSelectedAchievementImage(null)
        setSelectedTradeDetail(null)
        setSelectedPostDetail(null)
        setFeedDeepLinkPost(null)
        setSharePost(null)
      }
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [showCreatePost, editingPost, selectedAchievementImage, selectedTradeDetail, selectedPostDetail, feedDeepLinkPost, sharePost])

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
      const listProbe = await supabase
        .from("profiles")
        .select(PUBLIC_PROFILE_SELECT)
        .limit(50)
      console.log("PROFILE DEBUG (list up to 50 rows):", {
        rowCount: listProbe.data?.length ?? 0,
        error: listProbe.error,
        sampleIds: listProbe.data?.slice(0, 5).map((r: { id: string }) => r.id),
      })
    }

    let profileQuery = supabase.from("profiles").select(PUBLIC_PROFILE_SELECT)
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
      setAllTrades([])
      setVisibleTradeCount(PAGE_SIZE)
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

    setRoom(
      roomRow && roomRow.owner_user_id === prof.id ? roomRow : null
    )

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
    if (creatingRoomRef.current || creatingRoom) return
    creatingRoomRef.current = true
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
      creatingRoomRef.current = false
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
    if (creatingPostRef.current || creatingPost) return

    const text = postContent.trim()
    if (!text && !postImage && !pendingRoomShare) {
      showPopup({ type: "warning", message: "Add some text, an image, or a room share." })
      return
    }

    creatingPostRef.current = true
    setCreatingPost(true)

    try {
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
        showPopup(persistentError("Post Failed", upErr.message))
        return
      }

      const base = process.env.NEXT_PUBLIC_SUPABASE_URL
      imageUrl = base
        ? `${base}/storage/v1/object/public/profile_posts/${fileName}`
        : null
    }

    const insertPayload = pendingRoomShare
      ? buildRoomSharePostInsert(
          currentUserId,
          pendingRoomShare,
          text,
          imageUrl
        )
      : {
          user_id: currentUserId,
          content: text || null,
          image_url: imageUrl,
        }

    const { error } = await supabase.from("profile_posts").insert(insertPayload)

    if (error) {
      console.error(error)
      showPopup(
        persistentError("Post Failed", handleSupabaseError(error))
      )
      return
    }

    setShowCreatePost(false)
    setPostContent("")
    setPostImage(null)
    setPendingRoomShare(null)

    const { data } = await supabase
      .from("profile_posts")
      .select("*")
      .eq("user_id", profile.id)
      .order("created_at", { ascending: false })

    setWallPosts(data || [])
    showPopup(feedbackPresets.postPublished())
    notifyGettingStartedChecklistMaybeCompleted()
    } finally {
      creatingPostRef.current = false
      setCreatingPost(false)
    }
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
      supabase
        .from("profile_post_likes")
        .select("profile_post_id, user_id")
        .in("profile_post_id", ids),
      queryProfilePostComments((select) =>
        supabase
          .from("profile_post_comments")
          .select(select)
          .in("profile_post_id", ids)
          .order("created_at", { ascending: true })
      ),
    ])

    const likesMap: Record<string, { count: number; liked: boolean }> = {}
    for (const id of ids) {
      likesMap[String(id)] = { count: 0, liked: false }
    }
    for (const row of likesRows || []) {
      const key = String(row.profile_post_id)
      if (!likesMap[key]) likesMap[key] = { count: 0, liked: false }
      likesMap[key].count += 1
      if (currentUserId && row.user_id === currentUserId) likesMap[key].liked = true
    }

    const commentsMap: Record<string, any[]> = {}
    for (const id of ids) commentsMap[String(id)] = []
    for (const row of commentsRows || []) {
      const key = String(row.profile_post_id)
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
    }
    window.addEventListener("click", handleClick)
    return () => window.removeEventListener("click", handleClick)
  }, [])

  async function handleLike(id: string, type: "post" | "trade") {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    if (likeBusyRef.current.has(key) || likeBusyByPost[key]) return

    likeBusyRef.current.add(key)
    setLikeBusyByPost((prev) => ({ ...prev, [key]: true }))

    try {
    const meta = likesByPost[key] || { count: 0, liked: false }
    const postRow = posts.find((p) => String(p.id) === key)
    const ownerId = profilePostOwnerUserId(postRow ?? { user_id: profile?.id })
    if (meta.liked) {
      const { error } = await supabase
        .from("profile_post_likes")
        .delete()
        .eq("profile_post_id", key)
        .eq("user_id", currentUserId)
      if (error) return console.error(error)
      if (ownerId) {
        await deleteLikeNotification(supabase, {
          recipientUserId: ownerId,
          senderUserId: currentUserId,
          target: { kind: "profile_post", profilePostId: key },
        })
      }
      setLikesByPost((prev) => ({
        ...prev,
        [key]: { count: Math.max(0, meta.count - 1), liked: false },
      }))
      return
    }
    const { error } = await supabase.from("profile_post_likes").insert({
      profile_post_id: key,
      user_id: currentUserId,
    })
    if (error) return console.error(error)
    setLikesByPost((prev) => ({
      ...prev,
      [key]: { count: meta.count + 1, liked: true },
    }))

    if (ownerId) {
      await ensureLikeNotification(supabase, {
        recipientUserId: ownerId,
        senderUserId: currentUserId,
        target: { kind: "profile_post", profilePostId: key },
      })
    }
    } finally {
      likeBusyRef.current.delete(key)
      setLikeBusyByPost((prev) => ({ ...prev, [key]: false }))
    }
  }

  async function submitComment(
    id: string,
    type: "post" | "trade",
    parentCommentId?: string | null
  ) {
    if (!currentUserId || type !== "post") return
    const key = String(id)
    const text = (commentDraft[key] || "").trim()
    if (!text) return
    if (commentSubmittingRef.current.has(key) || commentSubmitting[key]) return

    commentSubmittingRef.current.add(key)
    setCommentSubmitting((s) => ({ ...s, [key]: true }))

    try {
    const postRow = posts.find((p) => String(p.id) === key)
    const existingComments = commentsByPost[key] || []
    const insertPayload: Record<string, unknown> = {
      profile_post_id: key,
      user_id: currentUserId,
      content: text,
    }
    if (parentCommentId) {
      insertPayload.parent_comment_id = parentCommentId
    }

    const { data, error } = await supabase
      .from("profile_post_comments")
      .insert(insertPayload)
      .select(PROFILE_POST_COMMENT_INSERT_SELECT)
      .single()
    if (error) return console.error(error)
    const insertedRow = withInsertedProfilePostParentCommentId(data, parentCommentId)
    setCommentsByPost((prev) => ({ ...prev, [key]: [...(prev[key] || []), insertedRow] }))
    setCommentDraft((prev) => ({ ...prev, [key]: "" }))

    const ownerId = profilePostOwnerUserId(postRow ?? { user_id: profile?.id })
    if (ownerId) {
      await insertProfilePostCommentNotifications(supabase, {
        profilePostId: key,
        commentId: String(insertedRow.id),
        ownerUserId: ownerId,
        senderUserId: currentUserId,
        content: text,
        parentCommentId,
        existingComments,
      })
    }
    } finally {
      commentSubmittingRef.current.delete(key)
      setCommentSubmitting((s) => ({ ...s, [key]: false }))
    }
  }

  async function deleteComment(comment: any) {
    if (!currentUserId) {
      console.warn("[comment-delete] aborted: no user")
      return false
    }
    if (String(comment.user_id) !== String(currentUserId)) {
      console.warn("[comment-delete] aborted: not author", {
        commentUserId: comment.user_id,
        currentUserId,
      })
      return false
    }

    const commentId = String(comment.id)
    const profilePostId = comment.profile_post_id
      ? String(comment.profile_post_id)
      : null
    const postId = comment.post_id ? String(comment.post_id) : null
    const tradeId = comment.trade_id ? String(comment.trade_id) : null

    let result:
      | Awaited<ReturnType<typeof deleteProfilePostComment>>
      | Awaited<ReturnType<typeof deleteFeedComment>>
      | Awaited<ReturnType<typeof deleteTradeComment>>
    let stateKey: string

    if (profilePostId) {
      result = await deleteProfilePostComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        profile_post_id: profilePostId,
      })
      stateKey = profilePostId
    } else if (postId) {
      result = await deleteFeedComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        post_id: postId,
      })
      stateKey = postId
    } else if (tradeId) {
      result = await deleteTradeComment(supabase, {
        id: commentId,
        user_id: currentUserId,
        content: comment.content,
        trade_id: tradeId,
      })
      stateKey = tradeId
    } else {
      console.error("[comment-delete] aborted: missing comment target", comment)
      return false
    }

    const { error, deleted } = result

    if (error || !deleted) {
      console.error("[comment-delete] failed", {
        commentId,
        userId: currentUserId,
        profilePostId,
        postId,
        tradeId,
        error,
      })
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return false
    }

    setCommentsByPost((prev) => ({
      ...prev,
      [stateKey]: filterCommentsAfterDelete(prev[stateKey] ?? [], commentId),
    }))

    if (feedDeepLinkPost && String(feedDeepLinkPost.id) === stateKey) {
      setFeedDeepLinkComments((prev) =>
        filterCommentsAfterDelete(prev, commentId)
      )
    }

    console.log("[comment-delete] local state updated", {
      commentId,
      stateKey,
    })

    return true
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

  function handleSharePost(post: any) {
    setSharePost(post)
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

    setAllTrades((prev) =>
      prev.map((t) =>
        String(t.id) === String(trade.id) ? { ...t, is_pinned: !t.is_pinned } : t
      )
    )
  }

  const performDeleteTrade = useCallback(async (tradeId: string) => {
    await deleteUserTrade(supabase, tradeId)
    setAllTrades((prev) => prev.filter((t) => String(t.id) !== String(tradeId)))
    setSelectedTradeDetail((prev) =>
      prev && String(prev.id) === String(tradeId) ? null : prev
    )
  }, [])

  const { requestDelete: handleDeleteTrade, confirmModalProps: deleteTradeConfirmProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

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
        setAllTrades([])
        setVisibleTradeCount(PAGE_SIZE)
      } else if (following && profile.is_private === true) {
        setVisibleTradeCount(PAGE_SIZE)
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

  const clearProfileQueryParams = useCallback(() => {
    if (!profile) return
    router.replace(profilePath(profile), { scroll: false })
  }, [profile, router])

  const loadFeedPostEngagement = useCallback(
    async (postId: string, openComments = false) => {
      const [{ data: likesRows }, { data: commentsRows }] = await Promise.all([
        supabase.from("likes").select("post_id, user_id").eq("post_id", postId),
        queryFeedComments((select) =>
          supabase
            .from("comments")
            .select(select)
            .eq("post_id", postId)
            .order("created_at", { ascending: true })
        ),
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
      if (!profile?.id || !canViewTrades) {
        clearProfileQueryParams()
        return
      }

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
    [canViewTrades, clearProfileQueryParams, loadFeedPostEngagement, profile?.id]
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
        const isOwner =
          currentUserId != null && String(currentUserId) === String(profile.id)
        const { data, error } = await supabase
          .from("trades")
          .select(isOwner ? "*" : PUBLIC_TRADE_SELECT)
          .eq("id", tradeId)
          .eq("user_id", profile.id)
          .eq("is_public", true)
          .maybeSingle()

        if (error || !data) {
          clearProfileQueryParams()
          return
        }
        trade = sanitizeTradeForViewer(data, { isOwner }) as typeof data
        setAllTrades((prev) => mergeUniqueById(prev, [trade]))
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

  useEffect(() => {
    if (!profile?.id || !currentUserId || loading) return
    if (searchParams.get("createPost") !== "1") return
    if (String(profile.id) !== String(currentUserId)) return

    const roomId = searchParams.get("shareRoom")?.trim() ?? ""

    async function openComposer() {
      setActiveTab("posts")

      if (roomId) {
        let draft: PendingRoomShareDraft | null = null

        try {
          const cached = sessionStorage.getItem("pendingRoomShareDraft")
          if (cached) {
            const parsed = JSON.parse(cached) as PendingRoomShareDraft
            if (parsed?.roomId === roomId) {
              draft = parsed
              sessionStorage.removeItem("pendingRoomShareDraft")
            }
          }
        } catch {
          // ignore invalid session draft
        }

        if (!draft) {
          const { data, error } = await supabase
            .from("rooms")
            .select("id, name, description, image_url")
            .eq("id", roomId)
            .maybeSingle()

          if (error || !data) {
            showPopup(
              persistentError(
                "Room Unavailable",
                "Could not load this room for sharing."
              )
            )
            clearProfileQueryParams()
            return
          }

          draft = pendingRoomShareFromRoom(data)
        }

        setPendingRoomShare(draft)
      }

      openCreatePostModal()
      clearProfileQueryParams()
    }

    void openComposer()
  }, [
    clearProfileQueryParams,
    currentUserId,
    loading,
    openCreatePostModal,
    profile?.id,
    searchParams,
    showPopup,
  ])

  const toggleFeedDeepLinkLike = useCallback(
    async (post: any) => {
      if (!currentUserId || feedDeepLinkLikeBusyRef.current) return
      const pid = String(post.id)
      const meta = feedDeepLinkLikeMeta
      const ownerId = postTradeOwnerUserId(post)

      feedDeepLinkLikeBusyRef.current = true

      try {
      if (meta.liked) {
        const { error } = await supabase
          .from("likes")
          .delete()
          .eq("post_id", pid)
          .eq("user_id", currentUserId)
        if (error) return
        if (ownerId) {
          await deleteLikeNotification(supabase, {
            recipientUserId: String(ownerId),
            senderUserId: currentUserId,
            target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
          })
        }
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

      if (ownerId && String(ownerId) !== currentUserId) {
        await ensureLikeNotification(supabase, {
          recipientUserId: String(ownerId),
          senderUserId: currentUserId,
          target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
        })
      }
      } finally {
        feedDeepLinkLikeBusyRef.current = false
      }
    },
    [currentUserId, feedDeepLinkLikeMeta]
  )

  const submitFeedDeepLinkComment = useCallback(
    async (post: any, text: string) => {
      if (!currentUserId || feedDeepLinkCommentSubmittingRef.current) return false
      const pid = String(post.id)
      const trimmed = (text || "").trim()
      if (!trimmed) return false

      feedDeepLinkCommentSubmittingRef.current = true
      setFeedDeepLinkCommentSubmitting(true)

      try {
      const { data, error } = await supabase
        .from("comments")
        .insert({
          post_id: pid,
          user_id: currentUserId,
          content: trimmed,
        })
        .select(FEED_COMMENT_INSERT_SELECT)
        .single()

      if (error) {
        console.error(error)
        return false
      }

      setFeedDeepLinkComments((prev) => [...prev, data])

      const ownerId = postTradeOwnerUserId(post)
      await ensureCommentNotificationsForInsert(supabase, {
        commentId: String(data.id),
        senderUserId: currentUserId,
        content: trimmed,
        target: { kind: "post", postId: pid, tradeId: post.trade_id ?? null },
        ownerUserId: ownerId,
        existingComments: feedDeepLinkComments,
      })

      return true
      } finally {
        feedDeepLinkCommentSubmittingRef.current = false
        setFeedDeepLinkCommentSubmitting(false)
      }
    },
    [currentUserId, feedDeepLinkComments]
  )

  const sortedTrades = [...trades].sort((a, b) => {
    if (a.is_pinned && !b.is_pinned) return -1
    if (!a.is_pinned && b.is_pinned) return 1
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  useEffect(() => {
    console.log(allTrades)
  }, [allTrades])

  const profilePublicTrades = useMemo(
    () => allTrades.filter((trade) => trade.is_public === true),
    [allTrades]
  )

  const filteredTrades = profilePublicTrades.filter((trade) => {
    if (selectedMode === "all") return true
    const m = selectedMode.toLowerCase()
    const modeStr = String(trade.mode ?? "").trim().toLowerCase()
    const typeStr = String(trade.account_type ?? "").trim().toLowerCase()
    return modeStr === m || typeStr === m
  })

  // Profile statistics use public trades only; backtest-mode trades are excluded.
  const analyticsTrades = filteredTrades.filter((trade) => {
    const modeStr = String(trade.mode ?? "").trim().toLowerCase()
    const typeStr = String(trade.account_type ?? "").trim().toLowerCase()
    return modeStr !== "backtest" && typeStr !== "backtest"
  })

  const profileOverviewTrades = profilePublicTrades.filter((trade) => {
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

  const losingPnls = analyticsTrades
    .map((t) => Number(t.pnl) || 0)
    .filter((pnl) => pnl < 0)
  const biggestLoss = losingPnls.length > 0 ? Math.min(...losingPnls) : null

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
  const overviewAvgRR = statsVisible
    ? averageRrFromTrades(profileOverviewTrades)
    : null
  const overviewPayoutTotal = statsVisible
    ? sumPayoutAchievementTotals(achievements)
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
        <SkeletonProfilePage />
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
  const ownedRoom =
    room && room.owner_user_id === profile.id ? room : null
  const hasRoom = !!ownedRoom
  const profileRoomKey =
    ownedRoom?.slug != null && String(ownedRoom.slug).trim() !== ""
      ? String(ownedRoom.slug)
      : ownedRoom?.id != null
        ? String(ownedRoom.id)
        : null
  const canShowVisitorRoomCta =
    canViewTrades &&
    ownedRoom != null &&
    ownedRoom.show_on_profile !== false &&
    profileRoomKey != null

  return (
    <>
      <Navbar />
      <FeedbackModal {...feedbackModalProps} />
      <ConfirmModal {...deleteTradeConfirmProps} />
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
                              Edit Profile
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

                    <p className="mt-2 whitespace-pre-wrap break-words px-4 text-sm leading-relaxed text-gray-300 md:px-0">
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
                                profileRoomKey!
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
                  ) : canShowVisitorRoomCta ? (
                    <div className="mt-3">
                      <button
                        type="button"
                        onClick={() =>
                          router.push(
                            `/trade-rooms?room=${encodeURIComponent(
                              profileRoomKey!
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
                      onClick={openCreatePostModal}
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
                  isOwnProfile ? (
                    <EmptyState
                      title="Share Your First Trade"
                      description="Your public trading history will appear here."
                      action={
                        <Link
                          href="/app"
                          className="text-sm font-medium text-blue-300 hover:text-blue-200"
                        >
                          Add Trade →
                        </Link>
                      }
                      className="py-10"
                    />
                  ) : !canViewTrades ? (
                    <PrivateProfileTabMessage variant="trades" />
                  ) : (
                    <p className="text-center text-sm text-gray-400">
                      No public trades yet.
                    </p>
                  )
                ) : (
                  <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
                    {sortedTrades.map((trade) => (
                      <div key={trade.id} id={`trade-${trade.id}`}>
                      <TradeCard
                        trade={{ ...trade, currentUserId }}
                        profile={profile}
                        shareProfile={viewerShareProfile}
                        canManageTrade={currentUserId === profile.id}
                        onStartEditTrade={() => {
                          openEditTradeModal(trade)
                        }}
                        onTogglePinTrade={() => void handlePinTrade(trade)}
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
                      setVisibleTradeCount((count) => count + PAGE_SIZE)
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
                  isOwnProfile ? (
                    <EmptyState
                      title="No Posts Yet"
                      description="Share trades and updates with the community."
                      action={
                        <button
                          type="button"
                          onClick={openCreatePostModal}
                          className="text-sm font-medium text-blue-300 hover:text-blue-200"
                        >
                          Create Post →
                        </button>
                      }
                      className="py-10"
                    />
                  ) : !canViewTrades ? (
                    <PrivateProfileTabMessage variant="posts" />
                  ) : (
                    <p className="text-center text-sm text-gray-400">
                      No posts yet.
                    </p>
                  )
                ) : (
                  <div className="grid grid-cols-1 gap-x-6 gap-y-8 md:grid-cols-2">
                    {sortedPosts.map((post) => {
                      const key = String(post.id)
                      return (
                        <div key={post.id} id={`post-${key}`}>
                        <PostCard
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
                          likeBusy={!!likeBusyByPost[key]}
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
                          onCommentSubmit={(parentCommentId) =>
                            void submitComment(key, "post", parentCommentId)
                          }
                          commentSubmitting={!!commentSubmitting[key]}
                          currentUserId={currentUserId}
                          onDeleteComment={deleteComment}
                          onSharePost={
                            currentUserId ? handleSharePost : undefined
                          }
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
                {!canViewTrades ? (
                  <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
                    <p className="text-lg text-gray-100">Private Profile</p>
                    <p className="mt-2 text-sm text-gray-400">
                      Follow this user to see their trades and stats.
                    </p>
                  </div>
                ) : (
                  <Calendar
                    trades={filteredTrades}
                    showAccountFilter={false}
                    showControls={false}
                    showAccountIdentifiers={isOwnProfile}
                  />
                )}
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
                          {biggestLoss != null ? formatPnlCurrency(biggestLoss) : "—"}
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
                      {achievements
                        .filter((a) => !a.is_featured)
                        .map((a) => {
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
              setPendingRoomShare(null)
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
                    setPendingRoomShare(null)
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
                placeholder={
                  pendingRoomShare
                    ? "Add a caption for your room share (optional)"
                    : "What's on your mind?"
                }
                rows={4}
                className="mb-3 w-full resize-none rounded-lg border border-white/10 bg-[#020617] p-2 text-sm text-white placeholder:text-gray-500"
              />

              {pendingRoomShare ? (
                <div className="mb-3">
                  <FeedRoomShareCard
                    post={{
                      room_id: pendingRoomShare.roomId,
                      room_name: pendingRoomShare.roomName,
                      room_logo: pendingRoomShare.roomLogo,
                      room_description: pendingRoomShare.roomDescription,
                    }}
                    viewerUserId={currentUserId}
                  />
                </div>
              ) : null}

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
          layout="split"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedTradeDetail(null)
            setTradeDetailFocusComments(false)
            setScreenshotLightboxUrl(null)
          }}
        >
          <TradeCard
            inDetailModal
            trade={selectedTradeDetail}
            profile={profile}
            shareProfile={viewerShareProfile}
            canManageTrade={currentUserId === profile.id}
            onStartEditTrade={() => {
              openEditTradeModal(selectedTradeDetail)
              setSelectedTradeDetail(null)
            }}
            onTogglePinTrade={() => void handlePinTrade(selectedTradeDetail)}
            onDeleteTrade={() => void handleDeleteTrade(String(selectedTradeDetail.id))}
            showInteractions={true}
            commentsExpanded
            scrollToCommentsOnMount={tradeDetailFocusComments}
            disableOpen
            onImageClick={setScreenshotLightboxUrl}
          />
        </DetailModalShell>
      ) : null}

      {selectedPostDetail ? (
        <DetailModalShell
          ariaLabel="Post details"
          title="Post"
          layout="split"
          backdropClassName="bg-black/75 backdrop-blur-md"
          onClose={() => {
            setSelectedPostDetail(null)
            setPostDetailFocusComments(false)
            setScreenshotLightboxUrl(null)
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
            likeBusy={!!likeBusyByPost[String(selectedPostDetail.id)]}
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
            onCommentSubmit={(parentCommentId) =>
              void submitComment(String(selectedPostDetail.id), "post", parentCommentId)
            }
            commentSubmitting={!!commentSubmitting[String(selectedPostDetail.id)]}
            currentUserId={currentUserId}
            onDeleteComment={deleteComment}
            disableOpen
            onImageClick={setScreenshotLightboxUrl}
            onSharePost={currentUserId ? handleSharePost : undefined}
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
          onDeleteComment={deleteComment}
          onSharePost={currentUserId ? handleSharePost : undefined}
        />
      ) : null}

      <ImageLightbox
        imageUrl={screenshotLightboxUrl}
        onClose={() => setScreenshotLightboxUrl(null)}
      />

      {sharePost ? (
        <ShareToConversationsModal
          open
          onClose={() => setSharePost(null)}
          title="Send Post"
          postId={String(sharePost.id)}
          feedKind="profile"
          post={sharePost}
          captionPlaceholder="Add a message..."
          showCancel={false}
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
              setVisibleTradeCount(PAGE_SIZE)
              void fetchTradesForProfile(profile.id).then(setAllTrades)
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
              isOwnProfile ? (
                <EmptyState
                  title="No Followers Yet"
                  description="Post consistently and engage with other traders to grow your audience."
                  className="py-6"
                />
              ) : (
                <p className="text-sm text-gray-400">No followers yet.</p>
              )
            ) : (
              <div className="space-y-1">
                {followersModalUsers.map((u) => (
                  <ProfileLink
                    key={u.id}
                    userId={u.id}
                    username={u.username}
                    onClick={closeFollowModals}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
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
                  </ProfileLink>
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
              isOwnProfile ? (
                <EmptyState
                  title="Not Following Anyone"
                  description="Follow traders to customize your feed."
                  action={
                    <Link
                      href="/explore"
                      className="text-sm font-medium text-blue-300 hover:text-blue-200"
                    >
                      Explore Traders →
                    </Link>
                  }
                  className="py-6"
                />
              ) : (
                <p className="text-sm text-gray-400">Not following anyone yet.</p>
              )
            ) : (
              <div className="space-y-1">
                {followingModalUsers.map((u) => (
                  <ProfileLink
                    key={u.id}
                    userId={u.id}
                    username={u.username}
                    onClick={closeFollowModals}
                    className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition hover:bg-white/10"
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
                  </ProfileLink>
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
          <SkeletonProfilePage />
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
