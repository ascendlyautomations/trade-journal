"use client"

import Link from "next/link"
import { useEffect, useRef, useState } from "react"
import DropdownMenu from "@/app/components/ui/DropdownMenu"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"
import {
  TradeSocialProvider,
  TradeSocialEngagementBar,
  TradeSocialCommentsSection,
} from "@/app/components/TradeSocialLayer"
import ShareTradeButton from "@/app/components/ShareTradeButton"
import { formatRR, formatTradePoints } from "@/lib/formatDisplay"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import ExpandableText from "@/app/components/ui/ExpandableText"
import FeedPostMetaRow from "@/app/components/feed/FeedPostMetaRow"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import { postImageSrc } from "@/app/components/feed/feedPostHelpers"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { formatPublicAccountTypeLabel } from "@/lib/publicAccountPrivacy"
import { isCopyTradedMode } from "@/lib/tradeMode"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import type { ReelRow } from "@/lib/reels"
import type {
  ProfileCardIdentity,
  ProfileTradeRow,
} from "./profileTypes"

function formatMoney(v: number) {
  return v < 0
    ? `-$${Math.abs(v).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${v.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

export type ProfileTradeCardProps = {
  trade: ProfileTradeRow
  profile: ProfileCardIdentity
  currentUserId?: string | null
  /** Logged-in viewer profile (referral_code for share PNG) */
  shareProfile?: { referral_code?: string | null } | null
  canManageTrade?: boolean
  onStartEditTrade?: () => void
  onTogglePinTrade?: () => void
  onDeleteTrade?: () => void
  showInteractions?: boolean
  onOpenDetail?: () => void
  onOpenComments?: () => void
  attachedReel?: ReelRow | null
  onOpenReplay?: () => void
  commentsExpanded?: boolean
  scrollToCommentsOnMount?: boolean
  inDetailModal?: boolean
  disableOpen?: boolean
  onImageClick?: (url: string) => void
}

export default function ProfileTradeCard({
  trade,
  profile,
  currentUserId,
  shareProfile,
  canManageTrade,
  onStartEditTrade,
  onTogglePinTrade,
  onDeleteTrade,
  showInteractions,
  onOpenDetail,
  onOpenComments,
  attachedReel,
  onOpenReplay,
  commentsExpanded = false,
  scrollToCommentsOnMount = false,
  inDetailModal = false,
  disableOpen,
  onImageClick,
}: ProfileTradeCardProps) {
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    Boolean(scrollToCommentsOnMount)
  )
  const imageSrc = postImageSrc(trade.image_url)
  const pnlRaw = Number(trade.pnl)
  const pnl = Number.isFinite(pnlRaw) ? pnlRaw : NaN
  const direction = trade.direction != null ? String(trade.direction) : "—"
  const ticker = trade.ticker != null ? String(trade.ticker) : "—"
  const accountTypeNorm = String(
    trade.account_type ?? trade.mode ?? ""
  )
    .trim()
    .toLowerCase()
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
  const showCopyBadge = isCopyTradedMode(trade)

  useEffect(() => {
    // This external focus request intentionally re-opens comments for deep links.
    // eslint-disable-next-line react-hooks/set-state-in-effect
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
      <span className="text-gray-400"> · </span>
      <span>
        {ticker} · {direction}
      </span>
    </>
  )

  const tradeDetails = (
    <>
      <div className="flex min-w-0 flex-wrap items-center justify-between gap-x-3 gap-y-1 overflow-hidden text-xs text-gray-100 md:text-sm">
        <div className="flex min-w-0 flex-wrap items-center gap-2">
          <span
            className={
              `shrink-0 text-sm font-bold tabular-nums md:text-base ${
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

          {showCopyBadge ? (
            <CopyTradedBadge trade={trade} className="shrink-0" />
          ) : accountTypeNorm ? (
            <span
              className={`
          shrink-0 rounded-full px-2 py-0.5 text-[10px] font-medium md:text-xs
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
        <div className="flex shrink-0 items-center gap-3 text-xs tabular-nums text-gray-300 md:text-sm">
          <span>RR {rr}</span>
          {pointsLabel ? <span>Pts {pointsLabel}</span> : null}
        </div>
      </div>
      {desc ? (
        <ExpandableText
          className="min-w-0 px-0.5 text-xs leading-snug text-white md:px-1 md:leading-relaxed md:text-sm"
          textClassName="break-words text-white"
          collapsedLines={3}
          stopPropagation
        >
          {desc}
        </ExpandableText>
      ) : null}
      <TradeCardTimingBlock
        trade={trade}
        onViewReel={
          attachedReel && onOpenReplay ? onOpenReplay : undefined
        }
      />
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
    <div className="flex shrink-0 items-center justify-between border-b border-white/5 px-3 py-2 md:px-4 md:py-3">
      <div className="flex min-w-0 items-center gap-2.5 md:gap-3">
        <ProfileAvatarImg
          src={profile.avatar_url}
          className="h-9 w-9 shrink-0 ring-2 ring-white/10 md:h-10 md:w-10"
        />
        <div className="min-w-0">
          <p className="truncate text-sm font-semibold text-white">
            {profile.username || "User"}
          </p>
          <FeedPostMetaRow
            label="Trade"
            labelClassName="font-medium text-amber-400/90"
            createdAt={trade.created_at}
            suffix={
              trade.is_pinned ? (
                <span className="ml-1.5" aria-label="Pinned">
                  📌
                </span>
              ) : null
            }
          />
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
    <div className="flex min-h-[80px] w-full items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] text-xs text-gray-400">
      No screenshot
    </div>
  )

  /** Mobile feed: ~35% shorter media frame with cover crop. Desktop unchanged. */
  const tradeFeedImage = imageSrc ? (
    <>
      <div className="relative h-[min(46dvh,280px)] w-full overflow-hidden md:hidden">
        <TradeScreenshotImage
          src={imageSrc}
          preset="feed-thumb"
          objectFit="cover"
          onClick={onImageClick}
          logContext="profile-trade-card-mobile"
          className="h-full w-full"
        />
      </div>
      <div className="hidden md:block">
        <TradeScreenshotImage
          src={imageSrc}
          preset="feed-thumb"
          onClick={onImageClick}
          logContext="profile-trade-card"
        />
      </div>
    </>
  ) : (
    <div className="flex min-h-[4rem] w-full items-center justify-center bg-gradient-to-br from-white/5 to-white/[0.02] py-6 text-xs text-gray-400 md:min-h-[5rem] md:py-8">
      No screenshot
    </div>
  )

  if (inDetailModal) {
    return (
      <article className={cardShellClass}>
        {imageSrc ? (
          <div className="hidden md:flex md:min-h-0 md:flex-1 md:items-center md:justify-center md:border-r md:border-white/10 md:p-3">
            {tradeImageBlock}
          </div>
        ) : null}

        <div className="flex min-h-0 flex-1 flex-col overflow-hidden md:w-[400px] md:shrink-0 lg:w-[420px]">
          {showInteractions ? (
            <TradeSocialProvider
              tradeId={trade.id}
              currentUserId={currentUserId ?? undefined}
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
                    meta={
                      <>
                        <FeedPostMetaRow
                          label="Trade"
                          labelClassName="font-medium text-amber-400/90"
                          createdAt={trade.created_at}
                        />
                        <div className="mt-0.5 truncate text-xs font-medium text-gray-300">
                          {tradeCompactMeta}
                        </div>
                      </>
                    }
                    onExpand={() => setCommentsFocused(false)}
                  />
                }
                mobileMedia={imageSrc ? tradeImageBlock : undefined}
                engagement={
                  <TradeSocialEngagementBar
                    onCommentsFocus={() => setCommentsFocused(true)}
                  />
                }
                engagementClassName="shrink-0 border-t border-white/10 px-3 py-1.5 md:border-t-0 md:px-4 md:py-2"
                collapsibleContent={
                  <div className="space-y-2 px-3 pb-2 pt-3 md:space-y-3 md:px-4 md:pb-3 md:pt-4">
                    {tradeDetails}
                  </div>
                }
                comments={
                  commentsExpanded ? (
                    <TradeSocialCommentsSection
                      className="px-3 pb-3 md:px-4 md:pb-4"
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
                <div className="shrink-0 md:hidden">{tradeImageBlock}</div>
              ) : null}
              <div className="space-y-2 p-3 md:space-y-3 md:p-4">{tradeDetails}</div>
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

      {tradeFeedImage}

      {showInteractions ? (
        <div onKeyDown={(e) => e.stopPropagation()}>
          <TradeSocialProvider
            tradeId={trade.id}
            currentUserId={currentUserId ?? undefined}
            tradeOwnerUserId={trade.user_id}
            commentsExpanded={commentsExpanded}
            onRequestComments={commentsExpanded ? undefined : onOpenComments}
            scrollToCommentsOnMount={scrollToCommentsOnMount}
          >
            <div className="border-t border-white/10 px-3 py-1.5 md:px-4 md:py-2">
              <TradeSocialEngagementBar />
            </div>
            <div className="space-y-2 px-3 pb-2 md:space-y-3 md:px-4 md:pb-3">
              {tradeDetails}
            </div>
            {commentsExpanded ? (
              <TradeSocialCommentsSection className="px-3 pb-3 md:px-4 md:pb-4" />
            ) : null}
          </TradeSocialProvider>
        </div>
      ) : (
        <div className="space-y-2 p-3 md:space-y-3 md:p-4">{tradeDetails}</div>
      )}
    </article>
  )
}