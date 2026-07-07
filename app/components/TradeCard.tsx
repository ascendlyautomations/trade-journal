"use client"

import ShareTradeButton from "./ShareTradeButton"
import TradeCardTimingBlock from "./TradeCardTimingBlock"
import {
  formatTradeClockTime,
  formatTradePrice,
  getTradeDurationDisplay,
} from "@/lib/tradeDisplayFormat"
import { formatEST } from "@/lib/formatEST"
import { formatMoneyUnknown, formatNumberUnknown, formatTradePoints } from "@/lib/formatDisplay"
import { formatTradeAccountNameSizeLine } from "@/lib/tradeAccountDisplay"
import { publicAccountBadgeFromTrade } from "@/lib/publicAccountPrivacy"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import TradeScreenshotImage from "@/app/components/trade/TradeScreenshotImage"

export type TradeCardProps = {
  trade: any
  /** Linked account row — name/size resolve from accounts when present. */
  accountRow?: { name?: string | null; account_size?: string | null } | null
  /** When false, only account-type badges are shown (no names, sizes, or IDs). */
  showAccountIdentifiers?: boolean
  showAdvanced?: boolean
  onEdit?: () => void
  onDelete?: () => void
  onAnalyze?: () => void
  onImageClick?: (fullImageUrl: string) => void
  /** Parent-loaded profile snippet for share export affiliate code */
  shareProfile?: { referral_code?: string | null } | null
}

export default function TradeCard({
  trade,
  accountRow = null,
  showAccountIdentifiers = true,
  showAdvanced = false,
  onEdit,
  onDelete,
  onAnalyze,
  onImageClick,
  shareProfile = null,
}: TradeCardProps) {
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

  if (process.env.NODE_ENV !== "production" && showAdvanced) {
    console.debug("[trade-card-duration-ui]", {
      tradeId: trade?.id ?? null,
      imported: String(trade?.account_type ?? "").toLowerCase() === "imported",
      durationText: trade?.duration_text ?? null,
      durationSeconds: trade?.duration_seconds ?? null,
      omittedFromUi: !showDuration,
    })
  }

  const modeLower = String(trade.mode ?? "").toLowerCase().trim()

  const accountDisplay = showAccountIdentifiers
    ? formatTradeAccountNameSizeLine(trade, accountRow)
    : (publicAccountBadgeFromTrade(trade) ?? "")

  const screenshotUrl = tradeScreenshotPublicUrl(trade.image_url)

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

  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-7 shadow backdrop-blur-md transition-all duration-200 hover:scale-[1.02] hover:border-white/20">
      <div className="flex flex-col gap-6 md:flex-row">
        <div className="min-w-0 flex-1 space-y-1 text-base text-gray-200">
          <h2 className="flex flex-wrap items-center gap-2 text-lg font-semibold">
            {trade.ticker} •{" "}
            {trade.direction ||
              (trade.exit_price && trade.entry_price
                ? trade.exit_price > trade.entry_price
                  ? "Long"
                  : "Short"
                : "Unknown")}
          </h2>

          <TradeCardTimingBlock trade={trade} />

          <div
            className={`mt-1 inline-block rounded-lg px-3 py-1 text-lg font-bold ${
              (Number(trade.pnl) || 0) >= 0
                ? "bg-green-500/20 text-green-400"
                : "bg-red-500/20 text-red-400"
            }`}
          >
            {formatMoneyUnknown(trade.pnl)}
          </div>

          <div className="mt-2 flex flex-wrap gap-2">
            <span className="rounded bg-white/10 px-2 py-1 text-xs">
              RR: {formatNumberUnknown(trade.rr)}
            </span>

            <span className="rounded bg-white/10 px-2 py-1 text-xs">
              Pts: {formatTradePoints(trade)}
            </span>
          </div>
          <p className="text-sm">
            <span className="text-gray-400">Contracts:</span>{" "}
            {trade.contracts != null
              ? Number(trade.contracts).toLocaleString()
              : "-"}
          </p>
          <p className="text-sm">
            <span className="text-gray-400">Session:</span> {trade.session}
          </p>

          <div className="mt-1 flex flex-wrap items-center gap-2">
            {modeLower === "backtest" ? (
              <span className="rounded bg-blue-500 px-2 py-1 text-xs text-white">
                Backtest
              </span>
            ) : accountDisplay.length > 0 ? (
              showAccountIdentifiers ? (
                <p className="text-sm text-gray-400">{accountDisplay}</p>
              ) : (
                <span className="rounded bg-white/10 px-2 py-1 text-xs text-gray-300">
                  {accountDisplay}
                </span>
              )
            ) : null}
          </div>

          {trade.public_description ? (
            <div className="mt-2 px-0">
              <p className="text-sm text-gray-300">
                <span className="text-gray-400">Public Description:</span>{" "}
                {trade.public_description}
              </p>
            </div>
          ) : null}

          {trade.strategy ? (
            <p className="text-xs text-gray-400">Strategy: {trade.strategy}</p>
          ) : null}

          <p className="text-sm">
            <span className="text-gray-400">Notes:</span> {trade.notes || "-"}
          </p>

          {showAdvanced ? (
            <div className="mt-3 space-y-1 border-t border-white/10 pt-3 text-sm text-gray-300">
              <p className="text-sm">
                <span className="text-gray-400">Entry:</span>{" "}
                {formatTradePrice(entryPrice)}
              </p>
              <p className="text-sm">
                <span className="text-gray-400">Exit:</span>{" "}
                {formatTradePrice(exitPrice)}
              </p>
              <p className="text-sm">
                <span className="text-gray-400">Entry Time:</span>{" "}
                {formatTradeClockTime(entryRaw, {
                  sameDayAs: trade.created_at,
                })}
              </p>
              <p className="text-sm">
                <span className="text-gray-400">Exit Time:</span>{" "}
                {formatTradeClockTime(exitRaw, {
                  sameDayAs: trade.created_at,
                })}
              </p>
              {showDuration ? (
                <p className="text-sm">
                  <span className="text-gray-400">Duration:</span>{" "}
                  {durationDisplay}
                </p>
              ) : null}
            </div>
          ) : null}
        </div>

        <div className="flex shrink-0 flex-col border-t border-white/10 pt-3 md:w-[250px] md:border-l md:border-t-0 md:pl-4 md:pt-0">
          <div className="flex flex-wrap items-center justify-end gap-2">
            {onEdit ? (
              <button
                type="button"
                onClick={onEdit}
                className="rounded bg-white/10 px-2 py-1 text-sm text-white transition hover:bg-white/20"
              >
                Edit
              </button>
            ) : null}
            {onAnalyze ? (
              <button
                type="button"
                onClick={onAnalyze}
                className="rounded bg-white/10 px-2 py-1 text-sm text-white transition hover:bg-white/20"
                aria-label="Analyze trade"
              >
                Analyze
              </button>
            ) : null}
            <ShareTradeButton
              variant="icon"
              trade={trade}
              profile={shareProfile}
              mode="full"
            />
            {onDelete ? (
              <button
                type="button"
                onClick={onDelete}
                className="rounded bg-white/10 px-2 py-1 text-sm text-white transition hover:bg-red-500/30 hover:text-red-200"
                aria-label="Delete trade"
              >
                Delete
              </button>
            ) : null}
          </div>

          {hasPsychology ? (
            <div className="mt-3 space-y-1">
              <p className="mb-2 text-sm text-gray-400">Psychology</p>
              {trade.confidence != null && trade.confidence !== "" && (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Confidence:</span>{" "}
                  {trade.confidence}
                </p>
              )}
              {trade.emotion != null && String(trade.emotion).trim() !== "" && (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Emotion:</span> {trade.emotion}
                </p>
              )}
              {trade.followed_plan != null && (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Followed Plan:</span>{" "}
                  {trade.followed_plan ? "Yes" : "No"}
                </p>
              )}
              {trade.mistake_type != null &&
                String(trade.mistake_type).trim() !== "" && (
                  <p className="text-sm text-gray-300">
                    <span className="text-gray-400">Mistake:</span>{" "}
                    {trade.mistake_type}
                  </p>
                )}
              {trade.market_condition != null &&
                String(trade.market_condition).trim() !== "" && (
                  <p className="text-sm text-gray-300">
                    <span className="text-gray-400">Market:</span>{" "}
                    {trade.market_condition}
                  </p>
                )}
              {trade.timeframe != null && String(trade.timeframe).trim() !== "" && (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Timeframe:</span>{" "}
                  {trade.timeframe}
                </p>
              )}
              {trade.news_event != null && (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">News Event:</span>{" "}
                  {trade.news_event ? "Yes" : "No"}
                </p>
              )}
              {trade.trade_type != null &&
                String(trade.trade_type).trim() !== "" && (
                  <p className="text-sm text-gray-300">
                    <span className="text-gray-400">Type:</span> {trade.trade_type}
                  </p>
                )}
              {trade.psychology_notes != null &&
                String(trade.psychology_notes).trim() !== "" && (
                  <p className="mt-2 text-sm text-gray-300">
                    <span className="text-gray-400">Psych Notes:</span>{" "}
                    {trade.psychology_notes}
                  </p>
                )}
            </div>
          ) : null}
        </div>
      </div>

      {screenshotUrl ? (
        <TradeScreenshotImage
          src={screenshotUrl}
          preset="trade-thumb"
          className="mt-4 rounded-lg border border-white/10"
          onClick={() => onImageClick?.(screenshotUrl)}
          logContext="trade-card"
        />
      ) : null}

      <p className="mt-4 text-xs text-gray-400">
        {formatEST(trade.created_at)}
      </p>
    </div>
  )
}
