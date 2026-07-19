"use client"

import { memo, useMemo } from "react"
import ShareTradeButton from "@/app/components/ShareTradeButton"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import {
  formatTradeClockTime,
  formatTradePrice,
  getTradeDurationDisplay,
} from "@/lib/tradeDisplayFormat"
import { formatEST } from "@/lib/formatEST"
import { formatMoneyUnknown, formatNumberUnknown, formatTradePoints } from "@/lib/formatDisplay"
import { safeAccountNumberLabel, formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import SavedImage from "@/app/components/ui/SavedImage"
import { TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS } from "@/lib/tradeScreenshotDisplay"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import TradeCopyTradingDetails from "@/app/components/trade/TradeCopyTradingDetails"
import ExpandableText from "@/app/components/ui/ExpandableText"
import { isCopyTradedTrade } from "@/lib/tradeCopyTrading"
import {
  isCopyTradedMode,
  resolveTradeModeBadgeLabel,
} from "@/lib/tradeMode"
import { type ReelRow } from "@/lib/reels"

export type TradesPageTradeCardProps = {
  trade: any
  showAdvanced: boolean
  accountRow?: any | null
  /** Optional account directory for Copy Trading source/destination labels. */
  accounts?: readonly any[]
  shareProfile?: { referral_code?: string | null } | null
  attachedReel?: ReelRow | null
  onOpenReplay?: () => void
  onEdit: (trade: any) => void
  onDelete: (tradeId: string) => void
  onSendClick: (trade: any) => void
  onAnalyze?: (trade: any) => void
  onImageClick: (imageUrl: string) => void
}

function TradesPageTradeCard({
  trade,
  showAdvanced,
  accountRow = null,
  accounts = [],
  shareProfile = null,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
  attachedReel = null,
  onOpenReplay,
}: TradesPageTradeCardProps) {
  const entryPrice = trade.entry_price ?? trade.entry ?? null
  const exitPrice = trade.exit_price ?? trade.exit ?? null
  const entryRaw = trade.entry_time
  const exitRaw = trade.exit_time

  const durationDisplay = getTradeDurationDisplay(
    trade.duration_text,
    trade.duration_seconds,
    entryRaw,
    exitRaw
  )
  const showDuration = durationDisplay !== null

  const acctLower = String(trade.mode ?? trade.account_type ?? "")
    .toLowerCase()
    .trim()
  const accountNumberDisplay = useMemo(
    () => safeAccountNumberLabel(accountRow?.account_number),
    [accountRow?.account_number]
  )

  const accountNameSizeLine = useMemo(
    () => formatTradeAccountNameSizeLine(trade, accountRow),
    [trade, accountRow]
  )

  const hasAccountLine = useMemo(
    () =>
      !!(
        accountNameSizeLine ||
        (accountRow?.account_number && accountNumberDisplay)
      ),
    [accountNameSizeLine, accountRow?.account_number, accountNumberDisplay]
  )

  const screenshotUrl = useMemo(
    () => tradeScreenshotPublicUrl(trade.image_url),
    [trade.image_url]
  )

  if (process.env.NODE_ENV !== "production" && showAdvanced) {
    console.debug("[trades-page-duration-ui]", {
      tradeId: trade?.id ?? null,
      imported: String(trade?.account_type ?? "").toLowerCase() === "imported",
      durationText: trade?.duration_text ?? null,
      durationSeconds: trade?.duration_seconds ?? null,
      omittedFromUi: !showDuration,
    })
  }

  const hasPsychology =
    (trade.confidence != null && trade.confidence !== "") ||
    (trade.emotion != null && String(trade.emotion).trim() !== "") ||
    trade.followed_plan != null ||
    (trade.mistake_type != null && String(trade.mistake_type).trim() !== "") ||
    (trade.market_condition != null &&
      String(trade.market_condition).trim() !== "") ||
    (trade.timeframe != null && String(trade.timeframe).trim() !== "") ||
    trade.news_event != null ||
    (trade.trade_type != null && String(trade.trade_type).trim() !== "") ||
    (trade.psychology_notes != null &&
      String(trade.psychology_notes).trim() !== "")

  const tradeDirection =
    trade.direction ||
    (trade.exit_price && trade.entry_price
      ? trade.exit_price > trade.entry_price
        ? "Long"
        : "Short"
      : "Unknown")

  const tradeTitle = (
    <>
      {trade.ticker} • {tradeDirection}
      {trade.is_public ? (
        <span className="text-xs font-normal text-green-400 md:ml-2">
          Public
        </span>
      ) : null}
    </>
  )

  const renderActionButtons = (compact: boolean) => (
    <>
      <button
        onClick={() => onEdit({ ...trade })}
        className={
          compact
            ? "flex items-center justify-center rounded-md bg-white/10 px-1.5 py-0.5 text-[11px] font-medium text-white transition hover:bg-white/20"
            : "flex items-center justify-center rounded-md bg-white/10 px-3 py-1 text-sm text-white transition hover:bg-white/20"
        }
        type="button"
      >
        Edit
      </button>
      {onAnalyze ? (
        <button
          onClick={() => onAnalyze(trade)}
          className={
            compact
              ? "flex items-center justify-center rounded-md bg-white/10 px-1.5 py-0.5 text-[11px] font-medium text-white transition hover:bg-white/20"
              : "flex items-center justify-center rounded-md bg-white/10 px-3 py-1 text-sm text-white transition hover:bg-white/20"
          }
          type="button"
          aria-label="Analyze trade"
        >
          {compact ? "AI" : "Analyze"}
        </button>
      ) : null}
      <ShareTradeButton
        trade={trade}
        variant="icon"
        profile={shareProfile}
        className={
          compact
            ? "flex items-center justify-center rounded-md bg-white/10 px-1.5 py-0.5 text-[11px] text-white transition hover:bg-white/20"
            : "flex items-center justify-center rounded-md bg-white/10 px-3 py-1.5 text-sm text-white transition hover:bg-white/20"
        }
        onSendClick={() => onSendClick(trade)}
      />
      <button
        onClick={() => onDelete(String(trade.id))}
        className={
          compact
            ? "flex items-center justify-center rounded-md bg-white/10 px-1.5 py-0.5 text-sm text-white transition hover:bg-white/20 hover:text-red-400 leading-none"
            : "text-white hover:text-red-400 text-xl transition leading-none"
        }
        type="button"
        aria-label="Delete trade"
      >
        🗑
      </button>
    </>
  )

  return (
    <div className="w-full min-w-0 overflow-hidden bg-white/5 border border-white/10 backdrop-blur-md px-2 py-3 md:px-4 rounded-xl shadow hover:border-white/20 transition-colors duration-200">
      <div className="flex flex-col gap-2.5 md:flex-row">
        <div className="min-w-0 flex-1 space-y-1 overflow-hidden text-sm text-gray-200 md:text-base">
          <div className="flex items-center justify-between gap-1.5 md:hidden">
            <h2 className="min-w-0 flex-1 text-base font-semibold leading-tight md:text-lg">
              <span className="inline-flex min-w-0 flex-wrap items-center gap-x-2 gap-y-0.5">
                {tradeTitle}
              </span>
            </h2>
            <div className="flex shrink-0 items-center gap-0.5">
              {renderActionButtons(true)}
            </div>
          </div>

          <h2 className="hidden text-lg font-semibold md:flex md:items-center md:gap-2 md:flex-wrap">
            {tradeTitle}
          </h2>

          <TradeCardTimingBlock
            trade={trade}
            onViewReel={
              attachedReel && onOpenReplay ? onOpenReplay : undefined
            }
          />

          <div
            className={`mt-1 inline-block rounded-lg px-3 py-1 text-base font-bold md:text-lg ${
              (Number(trade.pnl) || 0) >= 0
                ? "bg-green-500/20 text-green-400"
                : "bg-red-500/20 text-red-400"
            }`}
          >
            {formatMoneyUnknown(trade.pnl)}
          </div>

          <div className="mt-2 flex flex-wrap gap-2">
            <span className="rounded bg-white/10 px-2 py-1 text-[10px] md:text-xs">
              RR: {formatNumberUnknown(trade.rr)}
            </span>

            <span className="rounded bg-white/10 px-2 py-1 text-[10px] md:text-xs">
              Pts: {formatTradePoints(trade)}
            </span>

            {isCopyTradedTrade(trade) ? (
              <CopyTradedBadge trade={trade} />
            ) : null}
          </div>

          <p className="text-xs md:text-sm">
            <span className="text-gray-400">Contracts:</span>{" "}
            {trade.contracts != null
              ? Number(trade.contracts).toLocaleString()
              : "-"}
          </p>
          <p className="text-xs md:text-sm">
            <span className="text-gray-400">Session:</span> {trade.session}
          </p>

          <div className="mt-1 flex min-w-0 flex-wrap items-center gap-2">
            {!isCopyTradedMode(trade) &&
            resolveTradeModeBadgeLabel(trade, accountRow) ? (
              <span
                className={`rounded-full px-2 py-0.5 text-[10px] font-medium md:text-xs ${
                  acctLower === "funded"
                    ? "bg-green-500/20 text-green-400"
                    : acctLower === "eval"
                      ? "bg-yellow-500/20 text-yellow-400"
                      : acctLower === "live" ||
                          String(trade.trade_mode ?? "").toLowerCase() === "live"
                        ? "bg-blue-500/20 text-blue-400"
                        : acctLower === "backtest" ||
                            String(trade.trade_mode ?? "").toLowerCase() ===
                              "backtest"
                          ? "bg-indigo-500/20 text-indigo-300"
                          : String(trade.trade_mode ?? "").toLowerCase() ===
                              "sim"
                            ? "bg-cyan-500/20 text-cyan-300"
                            : String(trade.trade_mode ?? "").toLowerCase() ===
                                "replay"
                              ? "bg-purple-500/20 text-purple-300"
                              : "bg-gray-500/20 text-gray-400"
                }`}
              >
                {resolveTradeModeBadgeLabel(trade, accountRow)}
              </span>
            ) : null}

            {acctLower === "backtest" &&
            !trade.trade_mode &&
            !isCopyTradedMode(trade) ? (
              <span className="rounded bg-blue-500 px-2 py-1 text-[10px] text-white md:text-xs">
                Backtest
              </span>
            ) : null}

            {hasAccountLine ? (
              <div className="flex min-w-0 flex-wrap items-center gap-2 text-xs text-gray-300 md:text-sm">
                <span className="min-w-0 break-words">{accountNameSizeLine}</span>
                {accountNumberDisplay ? (
                  <span className="opacity-70">
                    • #{accountNumberDisplay}
                  </span>
                ) : null}
              </div>
            ) : null}

            {!resolveTradeModeBadgeLabel(trade, accountRow) &&
            !hasAccountLine &&
            !isCopyTradedMode(trade) ? (
              <span className="text-[10px] text-gray-400 md:text-xs">—</span>
            ) : null}
          </div>

          {trade.public_description ? (
            <ExpandableText
              className="mt-2 min-w-0 text-xs text-gray-300 md:text-sm"
              label="Public Description:"
              stopPropagation
            >
              {trade.public_description}
            </ExpandableText>
          ) : null}

          {trade.strategy ? (
            <p className="break-words text-[10px] text-gray-400 md:text-xs">
              Strategy: {trade.strategy}
            </p>
          ) : null}

          {trade.notes ? (
            <ExpandableText
              className="min-w-0 text-xs text-gray-300 md:text-sm"
              label="Notes:"
              stopPropagation
            >
              {trade.notes}
            </ExpandableText>
          ) : (
            <p className="text-xs md:text-sm">
              <span className="text-gray-400">Notes:</span> -
            </p>
          )}

          {showAdvanced ? (
            <div className="mt-3 space-y-1 border-t border-white/10 pt-3 text-xs text-gray-300 md:text-sm">
              <TradeCopyTradingDetails
                trade={trade}
                accounts={
                  accounts.length > 0
                    ? accounts
                    : accountRow
                      ? [accountRow]
                      : []
                }
                className="mb-2"
              />
              <p>
                <span className="text-gray-400">Entry:</span>{" "}
                {formatTradePrice(entryPrice)}
              </p>
              <p>
                <span className="text-gray-400">Exit:</span>{" "}
                {formatTradePrice(exitPrice)}
              </p>
              <p>
                <span className="text-gray-400">Entry Time:</span>{" "}
                {formatTradeClockTime(trade.entry_time, {
                  sameDayAs: trade.created_at,
                })}
              </p>
              <p>
                <span className="text-gray-400">Exit Time:</span>{" "}
                {formatTradeClockTime(trade.exit_time, {
                  sameDayAs: trade.created_at,
                })}
              </p>
              {showDuration ? (
                <p>
                  <span className="text-gray-400">Duration:</span>{" "}
                  {durationDisplay}
                </p>
              ) : null}
            </div>
          ) : null}
        </div>

        <div
          className={`flex shrink-0 flex-col md:w-[250px] md:border-l md:border-white/10 md:pl-4 md:pt-0 ${
            hasPsychology
              ? "border-t border-white/10 pt-3 md:border-t-0"
              : "hidden md:flex"
          }`}
        >
          <div className="hidden flex-wrap items-center justify-end gap-1 md:flex">
            {renderActionButtons(false)}
          </div>

          {hasPsychology ? (
            <div className="mt-3 space-y-1 text-xs md:text-sm">
              <p className="mb-2 text-xs text-gray-400 md:text-sm">Psychology</p>
              {trade.confidence != null && trade.confidence !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Confidence:</span>{" "}
                  {trade.confidence}
                </p>
              ) : null}
              {trade.emotion != null && String(trade.emotion).trim() !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Emotion:</span> {trade.emotion}
                </p>
              ) : null}
              {trade.followed_plan != null ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Followed Plan:</span>{" "}
                  {trade.followed_plan ? "Yes" : "No"}
                </p>
              ) : null}
              {trade.mistake_type != null &&
              String(trade.mistake_type).trim() !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Mistake:</span>{" "}
                  {trade.mistake_type}
                </p>
              ) : null}
              {trade.market_condition != null &&
              String(trade.market_condition).trim() !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Market:</span>{" "}
                  {trade.market_condition}
                </p>
              ) : null}
              {trade.timeframe != null && String(trade.timeframe).trim() !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Timeframe:</span>{" "}
                  {trade.timeframe}
                </p>
              ) : null}
              {trade.news_event != null ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">News Event:</span>{" "}
                  {trade.news_event ? "Yes" : "No"}
                </p>
              ) : null}
              {trade.trade_type != null &&
              String(trade.trade_type).trim() !== "" ? (
                <p className="text-gray-300">
                  <span className="text-gray-400">Type:</span> {trade.trade_type}
                </p>
              ) : null}
              {trade.psychology_notes != null &&
              String(trade.psychology_notes).trim() !== "" ? (
                <ExpandableText
                  className="mt-2 min-w-0 text-xs text-gray-300 md:text-sm"
                  label="Psych Notes:"
                  stopPropagation
                >
                  {trade.psychology_notes}
                </ExpandableText>
              ) : null}
            </div>
          ) : null}
        </div>
      </div>

      {screenshotUrl ? (
        <SavedImage
          src={screenshotUrl}
          alt=""
          maxHeightClassName={TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS}
          className="mx-auto mt-4 block rounded-lg"
          onClick={() => onImageClick(screenshotUrl)}
        />
      ) : null}

      {trade.created_at ? (
        <p className="mt-3 text-[10px] text-gray-400 md:text-xs">
          {formatEST(trade.created_at)}
        </p>
      ) : null}
    </div>
  )
}

export default memo(TradesPageTradeCard)
