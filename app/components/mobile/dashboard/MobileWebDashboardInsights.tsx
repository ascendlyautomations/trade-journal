"use client"

import type { ReactNode } from "react"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatSignedPnlDisplay } from "@/lib/formatDisplay"
import {
  insightCopyAlreadyCovers,
  insightRowKind,
  insightRowTitle,
  uniqueInsightCopy,
} from "@/lib/mobileWebDashboardAnalytics"
import { mwDashText } from "./mobileWebDashboardChrome"
import MobileWebDashboardEmptyCopy from "./MobileWebDashboardEmptyCopy"
import { MobileWebDashboardSectionHeader } from "./MobileWebDashboardChartBlock"

const INSIGHT_TOKEN = /(-?\$[\d,]+\.\d{2}|\d+%\s*win rate)/gi

function InsightCopy({
  text,
  force,
}: {
  text: string
  force?: "positive" | "negative" | "warning"
}) {
  if (force === "warning") {
    return <span className={mwDashText.warning}>{text}</span>
  }

  const parts = text.split(INSIGHT_TOKEN)
  return (
    <>
      {parts.map((part, index) => {
        if (!part) return null
        if (force === "positive") {
          return /(-?\$[\d,]+\.\d{2}|\d+%)/.test(part) ? (
            <span key={`${part}-${index}`} className={`font-semibold ${mwDashText.positive}`}>
              {part}
            </span>
          ) : (
            <span key={`${part}-${index}`}>{part}</span>
          )
        }
        if (force === "negative") {
          return /(-?\$[\d,]+\.\d{2}|\d+%)/.test(part) ? (
            <span key={`${part}-${index}`} className={`font-semibold ${mwDashText.negative}`}>
              {part}
            </span>
          ) : (
            <span key={`${part}-${index}`}>{part}</span>
          )
        }
        if (/^-?\$/.test(part)) {
          const negative = part.trimStart().startsWith("-")
          return (
            <span
              key={`${part}-${index}`}
              className={`font-semibold ${negative ? mwDashText.negative : mwDashText.positive}`}
            >
              {part}
            </span>
          )
        }
        if (/\d+%\s*win rate/i.test(part)) {
          const pct = parseInt(part, 10)
          return (
            <span
              key={`${part}-${index}`}
              className={`font-semibold ${
                Number.isFinite(pct) && pct >= 50 ? mwDashText.positive : mwDashText.negative
              }`}
            >
              {part}
            </span>
          )
        }
        return <span key={`${part}-${index}`}>{part}</span>
      })}
    </>
  )
}

type BestSetup = {
  strategy: string
  trades: number
  winRate: number
  totalPnL: number
}

type MobileWebDashboardInsightsProps = {
  showInsights: boolean
  showBestSetup: boolean
  showWorstSetup: boolean
  showWarnings: boolean
  totalTrades: number
  hasTradingDayTimeSource: boolean
  insights: string[]
  combinedInsights: string[]
  worstInsight: string | null
  warnings: string[]
  insightBestSymbol: string | null
  insightBestSymbolAvg: number
  insightBestWeekday: string | null
  insightBestWeekdayAvg: number
  bestSetup: BestSetup | null
  /** Accepted from the shared insights payload; unused on phone. */
  sections?: "all" | "performance" | "records"
}

function toneStroke(tone: "positive" | "negative" | "warning" | "neutral") {
  if (tone === "positive") return "var(--tt-positive, #3ddc97)"
  if (tone === "negative") return "var(--tt-negative, #ff7b72)"
  if (tone === "warning") return "var(--tt-warning, #e3b341)"
  return "var(--tt-accent, #4ec4e0)"
}

function InsightRow({
  title,
  tone,
  children,
  metric,
}: {
  title: string
  tone: "positive" | "negative" | "warning" | "neutral"
  children: ReactNode
  metric?: string
}) {
  const stroke = toneStroke(tone)
  return (
    <div
      className="rounded-[10px] px-3 py-2.5"
      style={{
        backgroundColor: "color-mix(in srgb, var(--tt-text) 6%, transparent)",
        boxShadow: `inset 0 0 0 0.5px color-mix(in srgb, ${stroke} 28%, transparent)`,
      }}
    >
      <div className="flex items-start gap-2.5">
        <span
          className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[13px] font-semibold"
          style={{
            color: stroke,
            backgroundColor: `color-mix(in srgb, ${stroke} 14%, transparent)`,
          }}
          aria-hidden
        >
          {tone === "positive" ? "+" : tone === "negative" ? "−" : tone === "warning" ? "!" : "i"}
        </span>
        <div className="min-w-0 flex-1">
          <p className={`text-[13px] font-semibold leading-snug ${mwDashText.primary}`}>
            {title}
          </p>
          <p className={`mt-0.5 text-[12px] leading-snug ${mwDashText.muted}`}>
            {children}
          </p>
          {metric ? (
            <p
              className="mt-1 text-[15px] font-semibold tabular-nums"
              style={{ color: stroke }}
            >
              {metric}
            </p>
          ) : null}
        </div>
      </div>
    </div>
  )
}

function Group({
  title,
  subtitle,
  children,
}: {
  title: string
  subtitle: string
  children: ReactNode
}) {
  return (
    <div className="flex flex-col gap-2">
      <div>
        <p className={`text-[13px] font-semibold ${mwDashText.primary}`}>{title}</p>
        <p className={`text-[11px] ${mwDashText.tertiary}`}>{subtitle}</p>
      </div>
      <div className="flex flex-col gap-2">{children}</div>
    </div>
  )
}

export default function MobileWebDashboardInsights({
  showInsights,
  showBestSetup,
  showWorstSetup,
  showWarnings,
  totalTrades,
  hasTradingDayTimeSource,
  insights,
  combinedInsights,
  worstInsight,
  warnings,
  insightBestSymbol,
  insightBestSymbolAvg,
  insightBestWeekday,
  insightBestWeekdayAvg,
  bestSetup,
}: MobileWebDashboardInsightsProps) {
  const uniqueInsights = uniqueInsightCopy(insights)
  const uniqueCombined = uniqueInsightCopy(combinedInsights)
  const uniqueWarnings = uniqueInsightCopy(warnings)
  const showSymbol =
    Boolean(insightBestSymbol) &&
    !insightCopyAlreadyCovers(uniqueInsights, insightBestSymbol)
  const showWeekday =
    Boolean(insightBestWeekday) &&
    !insightCopyAlreadyCovers(uniqueInsights, insightBestWeekday)

  const hasPerformance =
    uniqueInsights.length > 0 || showSymbol || showWeekday
  const hasAdvanced = uniqueCombined.length > 0
  const hasRisk = Boolean(worstInsight) || uniqueWarnings.length > 0
  const hasAnything =
    hasPerformance ||
    hasAdvanced ||
    hasRisk ||
    (showBestSetup && bestSetup)

  return (
    <div className="flex flex-col gap-5">
      <MobileWebDashboardSectionHeader
        title="Insights"
        subtitle="What your trading data is telling you"
      />

      {showBestSetup ? (
        <div
          className="rounded-[10px] px-3.5 py-3"
          style={{
            backgroundColor: "color-mix(in srgb, var(--tt-positive, #3ddc97) 10%, transparent)",
            boxShadow:
              "inset 0 0 0 0.5px color-mix(in srgb, var(--tt-positive, #3ddc97) 32%, transparent)",
          }}
        >
          <p className={`text-[11px] font-medium uppercase tracking-wide ${mwDashText.tertiary}`}>
            Best performing strategy
          </p>
          {bestSetup ? (
            <>
              <p className={`mt-1 text-[16px] font-semibold leading-snug ${mwDashText.primary}`}>
                {bestSetup.strategy}
              </p>
              <div className="mt-2 flex flex-wrap gap-x-3 gap-y-1 text-[12px] tabular-nums">
                <span className={mwDashText.positive}>
                  {formatCurrency(bestSetup.totalPnL)}
                </span>
                <span className={mwDashText.muted}>
                  {bestSetup.winRate.toFixed(0)}% WR
                </span>
                <span className={mwDashText.tertiary}>
                  {bestSetup.trades} trades
                </span>
              </div>
            </>
          ) : (
            <p className={`mt-1 text-[13px] ${mwDashText.muted}`}>
              Need at least 3 trades with the same strategy to rank setups.
            </p>
          )}
        </div>
      ) : null}

      {totalTrades > 0 && !hasTradingDayTimeSource ? (
        <MobileWebDashboardEmptyCopy
          title="Add entry and exit times"
          body="Trading day stats use a 6PM EST session rollover."
        />
      ) : null}

      {showInsights ? (
        hasPerformance ? (
          <Group
            title="Performance"
            subtitle="Session, symbol, and direction highlights"
          >
            {uniqueInsights.map((text) => {
              const kind = insightRowKind(text)
              return (
                <InsightRow
                  key={text}
                  title={insightRowTitle(kind)}
                  tone="neutral"
                >
                  <InsightCopy text={text} />
                </InsightRow>
              )
            })}
            {showSymbol && insightBestSymbol ? (
              <InsightRow
                title="Symbol"
                tone="positive"
                metric={`${formatSignedPnlDisplay(insightBestSymbolAvg)} avg`}
              >
                {insightBestSymbol} is your most profitable symbol
              </InsightRow>
            ) : null}
            {showWeekday && insightBestWeekday ? (
              <InsightRow
                title="Weekday"
                tone="positive"
                metric={`${formatSignedPnlDisplay(insightBestWeekdayAvg)} avg`}
              >
                {`You perform best on ${insightBestWeekday}s`}
              </InsightRow>
            ) : null}
          </Group>
        ) : (
          <MobileWebDashboardEmptyCopy
            title="Not enough sample size yet"
            body="Need at least 3 trades in a session, symbol, or direction bucket for the current filters."
          />
        )
      ) : null}

      {showInsights ? (
        <Group
          title="Advanced Edge"
          subtitle="Strongest combined setups (min. 3 trades)"
        >
          {hasAdvanced ? (
            uniqueCombined.map((text) => (
              <InsightRow key={text} title="Combined setup" tone="positive">
                <InsightCopy text={text} force="positive" />
              </InsightRow>
            ))
          ) : (
            <MobileWebDashboardEmptyCopy body="No qualifying combined setup yet." />
          )}
        </Group>
      ) : null}

      {showWorstSetup || showWarnings ? (
        <Group
          title="Risk & Behavior"
          subtitle="Setups to review and behavioral flags"
        >
          {showWorstSetup && worstInsight ? (
            <InsightRow title="Weakest setup" tone="negative">
              <InsightCopy text={worstInsight} force="negative" />
            </InsightRow>
          ) : null}
          {showWarnings
            ? uniqueWarnings.map((warning) => (
                <InsightRow key={warning} title="Behavior" tone="warning">
                  <InsightCopy text={warning} force="warning" />
                </InsightRow>
              ))
            : null}
          {showWorstSetup && !worstInsight && uniqueWarnings.length === 0 ? (
            <MobileWebDashboardEmptyCopy body="No combined setup to rank yet." />
          ) : null}
        </Group>
      ) : null}

      {!hasAnything && !showInsights ? (
        <MobileWebDashboardEmptyCopy body="Insights appear as your sample size grows." />
      ) : null}
    </div>
  )
}
