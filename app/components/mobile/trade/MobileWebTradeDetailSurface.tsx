"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { MoreHorizontal } from "lucide-react"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import TradeCopyTradingDetails from "@/app/components/trade/TradeCopyTradingDetails"
import {
  TradeSocialCommentsSection,
  TradeSocialEngagementBar,
  TradeSocialProvider,
} from "@/app/components/TradeSocialLayer"
import FeedPostHeader from "@/app/components/feed/FeedPostHeader"
import TradeDetailAuthorSubline from "@/app/components/trade/TradeDetailAuthorSubline"
import DropdownMenu from "@/app/components/ui/DropdownMenu"
import VaultDestinationModal from "@/app/components/vault/VaultDestinationModal"
import { MOBILE_WEB_CARD_CLASS } from "@/lib/mobileWebPageSurface"
import type { VaultContentRef } from "@/lib/vault/types"
import { useVault } from "@/lib/vault/VaultProvider"
import {
  formatRR,
  formatMoneyUnknown,
  formatNumberUnknown,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import TradeDetailMediaWithClipOverlay from "@/app/components/trade/TradeDetailMediaWithClipOverlay"
import {
  publicSocialHeaderAccountBadge,
  publicTradeCaptionFromRow,
  tradeExecutionClockLabel,
  tradeExecutionDateLabel,
} from "@/lib/tradeSocialDetailDisplay"
import {
  computeActualPoints,
  formatSignedPoints,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"
import { hasStoredTradePoints } from "@/lib/resolveTradePoints"
import { hasStoredRr } from "@/lib/tradeRr"
import { isCopyTradedTrade } from "@/lib/tradeCopyTrading"
import { resolveTradeDurationLabel } from "@/lib/tradeTimingDisplay"
import { storedPlannedDollarRisk } from "@/lib/plannedTradeRisk"
import { profilePath } from "@/lib/profileRoutes"
import { profileSeoDisplayName } from "@/lib/publicSeo"
import type { ReelRow } from "@/lib/reels"

type OwnerProfile = {
  id: string
  username?: string | null
  name?: string | null
  avatar_url?: string | null
} | null

type MobileWebTradeDetailSurfaceProps = {
  trade: any
  tradeId: string
  userId?: string
  ownerProfile: OwnerProfile
  ownerAccounts: any[]
  imgSrc: string | null
  attachedReel: ReelRow | null
  onOpenLightbox: (url: string) => void
  onViewReel: () => void
  onEdit?: () => void
  onDelete?: () => void
  onShare?: () => void
  onCopyLink?: () => void
  onAnalyze?: () => void
}

function StatCell({
  label,
  value,
  tone,
  subtitle,
  subtitleLine2,
}: {
  label: string
  value: string
  tone?: string
  subtitle?: string | null
  subtitleLine2?: string | null
}) {
  return (
    <div className="min-w-0">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
        {label}
      </p>
      <p
        className={`truncate text-[13px] font-semibold tabular-nums ${
          tone ?? "text-foreground"
        }`}
      >
        {value}
      </p>
      {subtitle ? (
        <p className="truncate text-[10px] text-muted-foreground">{subtitle}</p>
      ) : null}
      {subtitleLine2 ? (
        <p className="truncate text-[10px] text-muted-foreground tabular-nums">
          {subtitleLine2}
        </p>
      ) : null}
    </div>
  )
}

export default function MobileWebTradeDetailSurface({
  trade,
  tradeId,
  userId,
  ownerProfile,
  ownerAccounts,
  imgSrc,
  attachedReel,
  onOpenLightbox,
  onViewReel,
  onEdit,
  onDelete,
  onShare,
  onCopyLink,
  onAnalyze,
}: MobileWebTradeDetailSurfaceProps) {
  const isOwner = Boolean(userId && trade.user_id && String(trade.user_id) === userId)
  const ticker = String(trade.ticker ?? "").trim() || "—"
  const side = String(trade.direction ?? "").trim() || "—"
  const pnl = Number(trade.pnl)
  const pnlPositive = Number.isFinite(pnl) ? pnl >= 0 : true
  const pnlLabel = Number.isFinite(pnl) ? formatSignedPnlDisplay(pnl) : "—"
  const rrLabel = hasStoredRr(trade.rr) ? formatRR(trade.rr) : null
  const accountBadge = publicSocialHeaderAccountBadge(trade)
  const publicCaption = publicTradeCaptionFromRow(trade)
  const entryDate = tradeExecutionDateLabel(trade.entry_time ?? trade.created_at)
  const entryClock = tradeExecutionClockLabel(trade.entry_time)
  const exitDate = tradeExecutionDateLabel(trade.exit_time)
  const exitClock = tradeExecutionClockLabel(trade.exit_time)
  const pointsTargeted = hasStoredTradePoints(trade.points)
    ? Number(trade.points)
    : null
  const actualPoints = computeActualPoints(trade)
  const realizedRr = resolveRealizedRr(trade)
  const plannedRisk = storedPlannedDollarRisk(trade.dollar_risk)
  const plannedRiskLabel =
    plannedRisk != null
      ? formatMoneyUnknown(plannedRisk, { empty: "—" })
      : null
  const duration = resolveTradeDurationLabel(trade)
  const vaultRef: VaultContentRef = {
    contentType: "trade",
    contentID: tradeId,
  }
  const vault = useVault()
  const [vaultOpen, setVaultOpen] = useState(false)
  useEffect(() => {
    vault.prefetch([vaultRef])
  }, [vault, vaultRef.contentID])
  const vaulted = vault.stateFor(vaultRef).isVaulted
  const overflowItems = [
    ...(onShare ? [{ id: "share", label: "Share", onSelect: onShare }] : []),
    ...(onCopyLink
      ? [{ id: "copy", label: "Copy Link", onSelect: onCopyLink }]
      : []),
    ...(onAnalyze
      ? [{ id: "analyze", label: "Trade AI", onSelect: onAnalyze }]
      : []),
    {
      id: "vault",
      label: vaulted ? "Manage in Vault" : "Add to Vault",
      onSelect: () => {
        vault.loadFoldersIfNeeded()
        setVaultOpen(true)
      },
    },
    ...(onEdit ? [{ id: "edit", label: "Edit Trade", onSelect: onEdit }] : []),
    ...(onDelete
      ? [
          {
            id: "delete",
            label: "Delete Trade",
            variant: "danger" as const,
            onSelect: onDelete,
          },
        ]
      : []),
  ]

  const media = (
    <TradeDetailMediaWithClipOverlay
      imageSrc={imgSrc}
      displayMode={trade.image_display_mode as string | null | undefined}
      imageCrop={trade.image_crop}
      attachedReel={attachedReel}
      onOpenImage={(url) => onOpenLightbox(url)}
      onOpenClip={attachedReel ? onViewReel : undefined}
    />
  )

  const headline = (
    <div className="px-0.5">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1 space-y-0.5">
          <div className="flex min-w-0 flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
            <p className="text-[20px] font-semibold tracking-tight text-foreground">
              {ticker}
            </p>
            {accountBadge ? (
              <>
                <span className="text-[15px] font-medium text-muted-foreground/80">
                  |
                </span>
                <span className="text-[14px] font-medium text-muted-foreground">
                  {accountBadge}
                </span>
              </>
            ) : null}
          </div>
          <p
            className={`text-[11px] font-semibold uppercase tracking-wide ${
              /^long$/i.test(side)
                ? "text-emerald-400"
                : /^short$/i.test(side)
                  ? "text-red-400"
                  : "text-muted-foreground"
            }`}
          >
            {side}
          </p>
          {isCopyTradedTrade(trade) ? (
            <CopyTradedBadge trade={trade} className="mt-1" />
          ) : null}
        </div>
        <div className="shrink-0 text-right">
          <p
            className={`text-[20px] font-semibold tabular-nums ${
              pnlPositive ? "text-emerald-400" : "text-red-400"
            }`}
          >
            {pnlLabel}
          </p>
          {rrLabel ? (
            <p className="text-[13px] font-semibold tabular-nums text-muted-foreground">
              {rrLabel} R:R
            </p>
          ) : null}
        </div>
      </div>
    </div>
  )

  const caption = publicCaption ? (
    <p className="whitespace-pre-wrap px-0.5 text-[14px] leading-relaxed text-foreground">
      {publicCaption}
    </p>
  ) : null

  const stats = (
    <div className={`${MOBILE_WEB_CARD_CLASS} rounded-[18px] px-3 py-3`}>
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="P&L"
          value={pnlLabel}
          tone={pnlPositive ? "text-emerald-400" : "text-red-400"}
        />
        <StatCell label="Targeted R:R" value={rrLabel ?? "—"} />
        <StatCell
          label="Contracts"
          value={formatNumberUnknown(
            trade.contracts ?? trade.quantity ?? trade.size,
            "—"
          )}
        />
      </div>
      <div className="my-2.5 h-px bg-white/10" />
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="Points Targeted"
          value={formatSignedPoints(pointsTargeted)}
        />
        <StatCell label="Actual Points" value={formatSignedPoints(actualPoints)} />
        <StatCell
          label="Realized R:R"
          value={realizedRr != null ? formatRR(realizedRr) : "—"}
        />
      </div>
      {hasStoredRr(trade.max_rr_reached) ? (
        <>
          <div className="my-2.5 h-px bg-white/10" />
          <StatCell label="Max R:R Reached" value={formatRR(trade.max_rr_reached)} />
        </>
      ) : null}
      {plannedRiskLabel ? (
        <>
          <div className="my-2.5 h-px bg-white/10" />
          <StatCell label="Planned Risk ($)" value={plannedRiskLabel} />
        </>
      ) : null}
      <div className="my-2.5 h-px bg-white/10" />
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="Entry"
          value={formatMoneyUnknown(trade.entry_price ?? trade.entry, {
            empty: "—",
          })}
          subtitle={entryDate}
          subtitleLine2={entryClock}
        />
        <StatCell
          label="Exit"
          value={formatMoneyUnknown(trade.exit_price ?? trade.exit, {
            empty: "—",
          })}
          subtitle={exitDate}
          subtitleLine2={exitClock}
        />
        <StatCell label="Duration" value={duration ?? "—"} />
      </div>
    </div>
  )

  const ownerPrivateNotes =
    isOwner && trade.notes && String(trade.notes).trim() !== "" ? (
      <div className={`${MOBILE_WEB_CARD_CLASS} space-y-2 rounded-[18px] px-3 py-3`}>
        <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
          Private notes
        </p>
        <p className="text-[13px] leading-relaxed text-muted-foreground">
          {String(trade.notes)}
        </p>
      </div>
    ) : null

  const tradeAi = onAnalyze ? (
    <button
      type="button"
      onClick={onAnalyze}
      className={`${MOBILE_WEB_CARD_CLASS} w-full rounded-[18px] px-3 py-3 text-left`}
    >
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
        Trade AI
      </p>
      <p className="mt-1 text-[15px] font-semibold text-foreground">
        Analyze this trade
      </p>
      <p className="mt-0.5 text-[13px] text-muted-foreground">
        Open TradeTraxs AI with this trade selected.
      </p>
    </button>
  ) : null

  return (
    <div className="flex flex-col gap-3 pb-6 text-foreground">
      {!isOwner && ownerProfile ? (
        <FeedPostHeader
          userId={String(ownerProfile.id)}
          avatarUrl={ownerProfile.avatar_url ?? null}
          username={
            profileSeoDisplayName(ownerProfile) ||
            ownerProfile.username ||
            "User"
          }
          meta={
            <TradeDetailAuthorSubline
              username={ownerProfile.username}
              trade={trade}
            />
          }
        />
      ) : null}

      {isOwner ? (
        <>
          <div className="flex items-start gap-1">
            <div className="min-w-0 flex-1">{headline}</div>
            {overflowItems.length > 0 ? (
              <DropdownMenu
                align="right"
                trigger={
                  <span className="inline-flex h-11 w-11 items-center justify-center rounded-full text-muted-foreground">
                    <MoreHorizontal className="h-5 w-5" strokeWidth={2} aria-hidden />
                    <span className="sr-only">Trade actions</span>
                  </span>
                }
                items={overflowItems}
              />
            ) : null}
          </div>
          {caption}
          {stats}
          {media}
          {ownerPrivateNotes}
          <TradeCopyTradingDetails
            trade={trade}
            accounts={ownerAccounts}
          />
          {tradeAi}
          <VaultDestinationModal
            open={vaultOpen}
            onClose={() => setVaultOpen(false)}
            ref={vaultRef}
          />
        </>
      ) : (
        <TradeSocialProvider
          tradeId={tradeId}
          currentUserId={userId}
          tradeOwnerUserId={trade.user_id}
          enableRealtime
        >
          <div className="flex flex-col gap-3">
            {headline}
            {caption}
            {stats}
            {media}
            <TradeSocialEngagementBar className="px-1 py-1" />
            {ownerProfile ? (
              <Link
                href={profilePath(ownerProfile)}
                className="px-1 text-sm font-medium text-blue-300"
              >
                View {profileSeoDisplayName(ownerProfile)}&apos;s profile
              </Link>
            ) : null}
            <TradeSocialCommentsSection className="px-1 pb-2" />
          </div>
        </TradeSocialProvider>
      )}
    </div>
  )
}
