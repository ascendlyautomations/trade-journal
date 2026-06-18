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
import { formatMoneyUnknown, formatNumberUnknown } from "@/lib/formatDisplay"
import { safeAccountNumberLabel } from "@/lib/tradeAccountDisplay"

export type TradesPageTradeCardProps = {
  trade: any
  showAdvanced: boolean
  accountRow?: any | null
  shareProfile?: { referral_code?: string | null } | null
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
  shareProfile = null,
  onEdit,
  onDelete,
  onSendClick,
  onAnalyze,
  onImageClick,
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

  const hasAccountLine = useMemo(
    () =>
      !!(
        String(trade.account_name || "").trim() ||
        String(trade.account_size || "").trim() ||
        accountRow?.account_number && accountNumberDisplay
      ),
    [trade.account_name, trade.account_size, accountRow?.account_number, accountNumberDisplay]
  )

  const imageSrc = useMemo(() => {
    if (!trade.image_url) return null
    return trade.image_url.startsWith("http")
      ? trade.image_url
      : `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`
  }, [trade.image_url])

  const imageLightboxUrl = useMemo(() => {
    if (!trade.image_url) return null
    return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`
  }, [trade.image_url])

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

  return (
    <div className="w-full bg-white/5 border border-white/10 backdrop-blur-md px-2 py-3 md:px-4 rounded-xl shadow hover:scale-[1.02] hover:border-white/20 transition-all duration-200">
      <div className="flex flex-col gap-2.5 md:flex-row">
        <div className="min-w-0 flex-1 space-y-1 text-base text-gray-200">
          <h2 className="text-lg font-semibold flex items-center gap-2 flex-wrap">
            {trade.ticker} •{" "}
            {trade.direction ||
              (trade.exit_price && trade.entry_price
                ? trade.exit_price > trade.entry_price
                  ? "Long"
                  : "Short"
                : "Unknown")}
            {trade.is_public ? (
              <span className="text-xs font-normal text-green-400 ml-2">
                Public
              </span>
            ) : null}
          </h2>

          <TradeCardTimingBlock trade={trade} />

          <div
            className={`inline-block px-3 py-1 rounded-lg text-lg font-bold mt-1 ${
              (Number(trade.pnl) || 0) >= 0
                ? "bg-green-500/20 text-green-400"
                : "bg-red-500/20 text-red-400"
            }`}
          >
            {formatMoneyUnknown(trade.pnl)}
          </div>

          <div className="flex gap-2 mt-2 flex-wrap">
            <span className="bg-white/10 px-2 py-1 rounded text-xs">
              RR: {formatNumberUnknown(trade.rr)}
            </span>

            <span className="bg-white/10 px-2 py-1 rounded text-xs">
              Pts: {formatNumberUnknown(trade.points)}
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
            {trade.mode !== "backtest" && trade.account_type ? (
              <span
                className={`px-2 py-0.5 text-xs rounded-full font-medium ${
                  acctLower === "funded"
                    ? "bg-green-500/20 text-green-400"
                    : acctLower === "eval"
                      ? "bg-yellow-500/20 text-yellow-400"
                      : acctLower === "live"
                        ? "bg-blue-500/20 text-blue-400"
                        : acctLower === "backtest"
                          ? "bg-indigo-500/20 text-indigo-300"
                          : "bg-gray-500/20 text-gray-400"
                }`}
              >
                {trade.account_type}
              </span>
            ) : null}

            {acctLower === "backtest" ? (
              <span className="rounded bg-blue-500 px-2 py-1 text-xs text-white">
                Backtest
              </span>
            ) : null}

            {hasAccountLine ? (
              <div className="flex items-center gap-2 text-sm text-gray-300">
                <span>
                  {trade.account_name} {trade.account_size}
                </span>
                {accountNumberDisplay ? (
                  <span className="opacity-70">
                    • #{accountNumberDisplay}
                  </span>
                ) : null}
              </div>
            ) : null}

            {!trade.account_type && !hasAccountLine ? (
              <span className="text-xs text-gray-500">—</span>
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
            <div className="mt-3 text-sm text-gray-300 space-y-1 border-t border-white/10 pt-3">
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
                {formatTradeClockTime(trade.entry_time, {
                  sameDayAs: trade.created_at,
                })}
              </p>
              <p className="text-sm">
                <span className="text-gray-400">Exit Time:</span>{" "}
                {formatTradeClockTime(trade.exit_time, {
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
          <div className="flex flex-wrap items-center justify-end gap-1">
            <button
              onClick={() => onEdit({ ...trade })}
              className="flex items-center justify-center rounded-md bg-white/10 px-3 py-1 text-sm text-white transition hover:bg-white/20"
              type="button"
            >
              Edit
            </button>
            {onAnalyze ? (
              <button
                onClick={() => onAnalyze(trade)}
                className="flex items-center justify-center rounded-md bg-white/10 px-3 py-1 text-sm text-white transition hover:bg-white/20"
                type="button"
              >
                Analyze
              </button>
            ) : null}
            <ShareTradeButton
              trade={trade}
              variant="icon"
              profile={shareProfile}
              className="flex items-center justify-center rounded-md bg-white/10 px-3 py-1.5 text-sm text-white transition hover:bg-white/20"
              onSendClick={() => onSendClick(trade)}
            />
            <button
              onClick={() => onDelete(String(trade.id))}
              className="text-white hover:text-red-400 text-xl transition leading-none"
              type="button"
              aria-label="Delete trade"
            >
              🗑
            </button>
          </div>

          {hasPsychology ? (
            <div className="mt-3 space-y-1">
              <p className="text-sm text-gray-400 mb-2">Psychology</p>
              {trade.confidence != null && trade.confidence !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Confidence:</span>{" "}
                  {trade.confidence}
                </p>
              ) : null}
              {trade.emotion != null && String(trade.emotion).trim() !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Emotion:</span> {trade.emotion}
                </p>
              ) : null}
              {trade.followed_plan != null ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Followed Plan:</span>{" "}
                  {trade.followed_plan ? "Yes" : "No"}
                </p>
              ) : null}
              {trade.mistake_type != null &&
              String(trade.mistake_type).trim() !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Mistake:</span>{" "}
                  {trade.mistake_type}
                </p>
              ) : null}
              {trade.market_condition != null &&
              String(trade.market_condition).trim() !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Market:</span>{" "}
                  {trade.market_condition}
                </p>
              ) : null}
              {trade.timeframe != null && String(trade.timeframe).trim() !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Timeframe:</span>{" "}
                  {trade.timeframe}
                </p>
              ) : null}
              {trade.news_event != null ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">News Event:</span>{" "}
                  {trade.news_event ? "Yes" : "No"}
                </p>
              ) : null}
              {trade.trade_type != null &&
              String(trade.trade_type).trim() !== "" ? (
                <p className="text-sm text-gray-300">
                  <span className="text-gray-400">Type:</span> {trade.trade_type}
                </p>
              ) : null}
              {trade.psychology_notes != null &&
              String(trade.psychology_notes).trim() !== "" ? (
                <p className="text-sm text-gray-300 mt-2">
                  <span className="text-gray-400">Psych Notes:</span>{" "}
                  {trade.psychology_notes}
                </p>
              ) : null}
            </div>
          ) : null}
        </div>
      </div>

      {imageSrc ? (
        <img
          src={imageSrc}
          alt=""
          loading="lazy"
          decoding="async"
          className="w-full mt-4 rounded-lg border border-white/10 cursor-pointer"
          onClick={() => imageLightboxUrl && onImageClick(imageLightboxUrl)}
        />
      ) : null}

      {trade.created_at ? (
        <p className="text-xs text-gray-400 mt-3">{formatEST(trade.created_at)}</p>
      ) : null}
    </div>
  )
}

export default memo(TradesPageTradeCard)
