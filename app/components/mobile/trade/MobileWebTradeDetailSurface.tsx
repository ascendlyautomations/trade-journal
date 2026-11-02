"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { MoreHorizontal } from "lucide-react"
import ContentMediaPreview from "@/app/components/ContentMediaPreview"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import TradeCopyTradingDetails from "@/app/components/trade/TradeCopyTradingDetails"
import {
  TradeSocialCommentsSection,
  TradeSocialEngagementBar,
  TradeSocialProvider,
} from "@/app/components/TradeSocialLayer"
import FeedPostHeader from "@/app/components/feed/FeedPostHeader"
import ExpandableText from "@/app/components/ui/ExpandableText"
import DropdownMenu from "@/app/components/ui/DropdownMenu"
import ViewReelBadge from "@/app/components/feed/ViewReelBadge"
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
import { formatShortDateTimeEST } from "@/lib/formatDate"
import { formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"
import {
  computeActualPoints,
  formatSignedPoints,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"
import { hasStoredTradePoints } from "@/lib/resolveTradePoints"
import { hasStoredRr } from "@/lib/tradeRr"
import { isCopyTradedTrade } from "@/lib/tradeCopyTrading"
import { resolveTradeDurationLabel } from "@/lib/tradeTimingDisplay"
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
}: {
  label: string
  value: string
  tone?: string
  subtitle?: string | null
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
  const dateLine =
    formatShortDateTimeEST(trade.entry_time || trade.created_at || trade.trade_date) ||
    ""
  const accountLine = formatTradeAccountNameSizeLine(
    trade,
    ownerAccounts.find((row) => String(row.id) === String(trade.account_id ?? ""))
  )
  const pointsTargeted = hasStoredTradePoints(trade.points)
    ? Number(trade.points)
    : null
  const actualPoints = computeActualPoints(trade)
  const realizedRr = resolveRealizedRr(trade)
  const duration = resolveTradeDurationLabel(trade)
  const entryStamp = trade.entry_time
    ? formatShortDateTimeEST(trade.entry_time)
    : null
  const exitStamp = trade.exit_time
    ? formatShortDateTimeEST(trade.exit_time)
    : null
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

  const media = imgSrc ? (
    <button
      type="button"
      onClick={() => onOpenLightbox(imgSrc)}
      className="block w-full overflow-hidden rounded-[14px]"
    >
      <ContentMediaPreview
        src={imgSrc}
        preset="feed-detail"
        displayMode={trade.image_display_mode as string | null | undefined}
        imageCrop={trade.image_crop}
      />
    </button>
  ) : null

  const headline = (
    <div className="px-0.5">
      <div className="flex items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-[20px] font-semibold tracking-tight text-foreground">
            {ticker}
          </p>
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
          {dateLine ? (
            <p className="mt-0.5 text-[12px] text-muted-foreground">{dateLine}</p>
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
      {isCopyTradedTrade(trade) ? (
        <div className="mt-2">
          <CopyTradedBadge trade={trade} />
        </div>
      ) : accountLine ? (
        <p className="mt-1 truncate text-[12px] text-muted-foreground">
          {accountLine}
        </p>
      ) : null}
    </div>
  )

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
      <div className="my-2.5 h-px bg-white/10" />
      <div className="grid grid-cols-3 gap-3">
        <StatCell
          label="Entry"
          value={formatMoneyUnknown(trade.entry_price ?? trade.entry, {
            empty: "—",
          })}
          subtitle={entryStamp}
        />
        <StatCell
          label="Exit"
          value={formatMoneyUnknown(trade.exit_price ?? trade.exit, {
            empty: "—",
          })}
          subtitle={exitStamp}
        />
        <StatCell label="Duration" value={duration ?? "—"} />
      </div>
    </div>
  )

  const notes = trade.notes || trade.public_description ? (
    <div className={`${MOBILE_WEB_CARD_CLASS} space-y-2 rounded-[18px] px-3 py-3`}>
      <p className="text-[10px] font-semibold uppercase tracking-wide text-muted-foreground">
        Journal
      </p>
      {trade.public_description ? (
        <ExpandableText
          className="text-[14px] leading-relaxed text-foreground"
          textClassName="text-foreground"
        >
          {trade.public_description}
        </ExpandableText>
      ) : null}
      {trade.notes && trade.notes !== trade.public_description ? (
        <p className="text-[13px] leading-relaxed text-muted-foreground">
          {String(trade.notes)}
        </p>
      ) : null}
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
          username={ownerProfile.username || ownerProfile.name || "User"}
          metaLabel="Trade"
          metaLabelClassName="font-medium text-amber-400/90"
          postedAt={trade.created_at}
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
          {stats}
          {notes}
          {media}
          {attachedReel ? (
            <ViewReelBadge onClick={() => onViewReel()} />
          ) : null}
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
            {media}
            {media ? (
              <TradeSocialEngagementBar className="px-1 py-1" />
            ) : null}
            {headline}
            {stats}
            {!media ? (
              <TradeSocialEngagementBar className="px-1 py-1" />
            ) : null}
            {notes}
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
