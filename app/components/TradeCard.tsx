"use client"

import { useEffect, useState } from "react"
import ShareTradeButton from "./ShareTradeButton"
import { supabase } from "@/lib/supabaseClient"
import { formatTradeAccountDisplay } from "@/lib/tradeAccountDisplay"
import {
  formatTradeClockTime,
  formatTradePrice,
  getTradeDurationDisplay,
} from "@/lib/tradeDisplayFormat"
import { formatDateOnly, formatTimeOnly } from "@/lib/formatDate"
import { formatEST } from "@/lib/formatEST"

function formatMoney(value: unknown): string {
  if (value === null || value === undefined) return "-"
  const number = Number(value)
  if (Number.isNaN(number)) return "-"
  return number < 0
    ? `-$${Math.abs(number).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
    : `$${number.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      })}`
}

function formatNumber(value: unknown): string {
  if (value === null || value === undefined) return "-"
  const number = Number(value)
  if (Number.isNaN(number)) return "-"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
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

let accountsLoadPromise: Promise<Record<string, any>> | null = null

async function loadAccountMap(): Promise<Record<string, any>> {
  if (!accountsLoadPromise) {
    accountsLoadPromise = (async () => {
      const { data } = await supabase.from("accounts").select("*")
      const accountMap: Record<string, any> = {}
      ;(data ?? []).forEach((acc: any) => {
        accountMap[acc.id] = acc
      })
      return accountMap
    })()
  }
  return accountsLoadPromise
}

export type TradeCardProps = {
  trade: any
  showAdvanced?: boolean
  onEdit?: () => void
  onDelete?: () => void
  onImageClick?: (fullImageUrl: string) => void
  /** Parent-loaded profile snippet for share export affiliate code */
  shareProfile?: { referral_code?: string | null } | null
  /** Optional id → account row map (avoids fetch when parent already loaded accounts) */
  accountById?: Record<string, any> | null
}

export default function TradeCard({
  trade,
  showAdvanced = false,
  onEdit,
  onDelete,
  onImageClick,
  shareProfile = null,
  accountById = null,
}: TradeCardProps) {
  console.log("REAL TRADE CARD RENDERED")

  console.log("FINAL TRADE CHECK:", trade)

  const entryPrice = trade.entry_price ?? trade.entry ?? null
  const exitPrice = trade.exit_price ?? trade.exit ?? null

  const entryRaw = trade.entry_time
  const exitRaw = trade.exit_time
  const entry = entryRaw ? formatTimeOnly(entryRaw) : null
  const exit = exitRaw ? formatTimeOnly(exitRaw) : null
  const duration = getDuration(entryRaw, exitRaw)

  if (process.env.NODE_ENV === "development") {
    console.log("TRADE TIMES FINAL:", { entryRaw, exitRaw, entry, exit, duration })
  }

  const durationDisplay = getTradeDurationDisplay(
    trade.duration_text,
    trade.duration_seconds
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

  const [accountMap, setAccountMap] = useState<Record<string, any> | null>(
    () => accountById ?? null
  )

  useEffect(() => {
    if (trade.account) {
      return
    }
    if (accountById) {
      setAccountMap(accountById)
      return
    }
    let cancelled = false
    loadAccountMap().then((m) => {
      if (!cancelled) setAccountMap(m)
    })
    return () => {
      cancelled = true
    }
  }, [accountById, trade.account])

  const acc =
    trade.account ??
    (accountMap && trade.account_id != null
      ? accountMap[String(trade.account_id)]
      : undefined)

  const accountDisplay = formatTradeAccountDisplay({
    ...trade,
    account: acc ?? undefined,
  })

  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  const screenshotUrl = trade.image_url
    ? trade.image_url.startsWith("http")
      ? trade.image_url
      : base
        ? `${base}/storage/v1/object/public/screenshots/${trade.image_url}`
        : null
    : null

  return (
    <div className="relative rounded-xl border border-white/10 bg-white/5 p-7 shadow backdrop-blur-md transition-all duration-200 hover:scale-[1.02] hover:border-white/20">
      <div className="absolute right-3 top-3 flex items-center gap-2">
        {onEdit ? (
          <button
            type="button"
            onClick={onEdit}
            className="rounded bg-white/10 px-2 py-1 text-sm text-white transition hover:bg-white/20"
          >
            Edit
          </button>
        ) : null}
        <ShareTradeButton variant="icon" trade={trade} profile={shareProfile} mode="full" />
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

      <div className="flex flex-col gap-6 md:flex-row">
        <div className="flex-1">
          <div className="space-y-1 text-base text-gray-200">
            <h2 className="flex flex-wrap items-center gap-2 text-lg font-semibold">
              {trade.ticker} •{" "}
              {trade.direction ||
                (trade.exit_price && trade.entry_price
                  ? trade.exit_price > trade.entry_price
                    ? "Long"
                    : "Short"
                  : "Unknown")}
            </h2>

            <p className="text-red-400 text-xs">
              RAW ENTRY: {String(trade.entry_time)}
            </p>
            <p className="text-red-400 text-xs">
              RAW EXIT: {String(trade.exit_time)}
            </p>
            <p className="text-yellow-400 text-xs">
              TEST ENTRY: {new Date(trade.entry_time).toString()}
            </p>
            <p className="text-yellow-400 text-xs">
              TEST EXIT: {new Date(trade.exit_time).toString()}
            </p>

            <p className="text-xs text-gray-400">
              {formatDateOnly(
                trade.entry_time || trade.date || trade.created_at || undefined
              )}
              {entry ? ` • ${entry}` : ""}
              {exit ? ` – ${exit}` : ""}
              {duration ? ` (${duration})` : ""}
            </p>

            <div
              className={`mt-1 inline-block rounded-lg px-3 py-1 text-lg font-bold ${
                (Number(trade.pnl) || 0) >= 0
                  ? "bg-green-500/20 text-green-400"
                  : "bg-red-500/20 text-red-400"
              }`}
            >
              {formatMoney(trade.pnl)}
            </div>

            <div className="mt-2 flex flex-wrap gap-2">
              <span className="rounded bg-white/10 px-2 py-1 text-xs">
                RR: {formatNumber(trade.rr)}
              </span>

              <span className="rounded bg-white/10 px-2 py-1 text-xs">
                Pts: {formatNumber(trade.points)}
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
                <p className="text-sm text-gray-400">{accountDisplay}</p>
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
        </div>

        {(trade.confidence != null && trade.confidence !== "") ||
        (trade.emotion != null && String(trade.emotion).trim() !== "") ||
        trade.followed_plan != null ||
        (trade.mistake_type != null &&
          String(trade.mistake_type).trim() !== "") ||
        (trade.market_condition != null &&
          String(trade.market_condition).trim() !== "") ||
        (trade.timeframe != null && String(trade.timeframe).trim() !== "") ||
        trade.news_event != null ||
        (trade.trade_type != null && String(trade.trade_type).trim() !== "") ||
        (trade.psychology_notes != null &&
          String(trade.psychology_notes).trim() !== "") ? (
          <div className="shrink-0 space-y-1 border-t border-white/10 pt-3 md:w-[250px] md:border-l md:border-t-0 md:pl-4 md:pt-0">
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
                <span className="text-gray-400">News:</span>{" "}
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

      {screenshotUrl ? (
        <img
          src={screenshotUrl}
          alt=""
          className="mt-4 w-full cursor-pointer rounded-lg border border-white/10"
          onClick={() => onImageClick?.(screenshotUrl)}
        />
      ) : null}

      <p className="mt-4 text-xs text-gray-400">
        {formatEST(trade.created_at)}
      </p>
    </div>
  )
}
