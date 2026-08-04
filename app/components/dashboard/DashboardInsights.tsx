"use client"

import { memo } from "react"
import {
  NegativeInsightLine,
  PerformanceInsightLine,
  PositiveInsightLine,
  SymbolInsightLine,
  WarningInsightLine,
  WeekdayInsightLine,
} from "./DashboardInsightHighlight"
import {
  dashboardInsightBodyClass,
  dashboardInsightCardClass,
  dashboardInsightEmptyClass,
  dashboardInsightHelperClass,
  dashboardInsightLabelClass,
  dashboardInsightMetricNegativeClass,
  dashboardInsightMetricNeutralClass,
  dashboardInsightMetricPositiveClass,
  dashboardInsightTitleClass,
} from "./dashboardInsightStyles"
import { formatCurrency } from "@/lib/formatCurrency"

type BestSetup = {
  strategy: string
  trades: number
  winRate: number
  totalPnL: number
}

type DashboardInsightsProps = {
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
  /**
   * Mobile tab split. Desktop / default keeps `"all"`.
   * - performance: Performance Insights card only
   * - records: setups, advanced edge, risk, warnings
   */
  sections?: "all" | "performance" | "records"
}

function PerformanceInsightsCard({
  totalTrades,
  hasTradingDayTimeSource,
  insights,
  insightBestSymbol,
  insightBestSymbolAvg,
  insightBestWeekday,
  insightBestWeekdayAvg,
}: Pick<
  DashboardInsightsProps,
  | "totalTrades"
  | "hasTradingDayTimeSource"
  | "insights"
  | "insightBestSymbol"
  | "insightBestSymbolAvg"
  | "insightBestWeekday"
  | "insightBestWeekdayAvg"
>) {
  return (
    <div className={dashboardInsightCardClass}>
      <h3 className={dashboardInsightTitleClass}>Performance Insights</h3>
      <p className={dashboardInsightHelperClass}>
        Data-driven highlights (min. 3 trades per session, symbol, or direction).
        Respects current filters.
      </p>
      {totalTrades > 0 && !hasTradingDayTimeSource ? (
        <p className="mb-3 text-xs md:text-sm leading-relaxed text-amber-200/90">
          Trading day stats use entry/exit times with a 6PM EST session rollover.
          Add entry/exit times to unlock these insights.
        </p>
      ) : null}
      {insights.length > 0 || insightBestSymbol || insightBestWeekday ? (
        <div className="space-y-2">
          {insights.map((text, index) => (
            <p
              key={`${index}-${text.slice(0, 24)}`}
              className={dashboardInsightBodyClass}
            >
              • <PerformanceInsightLine text={text} />
            </p>
          ))}
          {insightBestSymbol ? (
            <p className={dashboardInsightBodyClass}>
              •{" "}
              <SymbolInsightLine
                symbol={insightBestSymbol}
                avgPnL={insightBestSymbolAvg}
              />
            </p>
          ) : null}
          {insightBestWeekday ? (
            <p className={dashboardInsightBodyClass}>
              •{" "}
              <WeekdayInsightLine
                weekday={insightBestWeekday}
                avgPnL={insightBestWeekdayAvg}
              />
            </p>
          ) : null}
        </div>
      ) : (
        <p className={dashboardInsightEmptyClass}>
          Not enough sample size yet. Need at least 3 trades in a session,
          symbol, or direction bucket (with current filters).
        </p>
      )}
    </div>
  )
}

function BestSetupCard({
  bestSetup,
  wide,
}: {
  bestSetup: BestSetup | null
  wide?: boolean
}) {
  return (
    <div className={`${dashboardInsightCardClass} ${wide ? "md:col-span-2" : ""}`}>
      <h3 className={dashboardInsightTitleClass}>Best Performing Strategy</h3>
      {bestSetup ? (
        <div className={`space-y-2 ${dashboardInsightBodyClass}`}>
          <p>
            <span className={dashboardInsightLabelClass}>Strategy:</span>{" "}
            <span className={dashboardInsightMetricPositiveClass}>
              {bestSetup.strategy}
            </span>
          </p>
          <p>
            <span className={dashboardInsightLabelClass}>Win rate:</span>{" "}
            <span
              className={
                bestSetup.winRate > 50
                  ? dashboardInsightMetricPositiveClass
                  : dashboardInsightMetricNegativeClass
              }
            >
              {bestSetup.winRate.toFixed(1)}%
            </span>
          </p>
          <p>
            <span className={dashboardInsightLabelClass}>Total P&amp;L:</span>{" "}
            <span
              className={`tabular-nums ${
                bestSetup.totalPnL >= 0
                  ? dashboardInsightMetricPositiveClass
                  : dashboardInsightMetricNegativeClass
              }`}
            >
              {formatCurrency(bestSetup.totalPnL)}
            </span>
          </p>
          <p>
            <span className={dashboardInsightLabelClass}>Trades:</span>{" "}
            <span className={dashboardInsightMetricNeutralClass}>
              {bestSetup.trades}
            </span>
          </p>
        </div>
      ) : (
        <p className={dashboardInsightEmptyClass}>
          Need at least 3 trades with the same strategy to rank setups.
        </p>
      )}
    </div>
  )
}

function DashboardInsights({
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
  sections = "all",
}: DashboardInsightsProps) {
  const includePerformance = sections === "all" || sections === "performance"
  const includeRecords = sections === "all" || sections === "records"

  const showPerformanceCard = includePerformance && showInsights
  const showBestSetupCard = includeRecords && showBestSetup
  const showNarrativeRow =
    includeRecords && (showInsights || showWorstSetup || showWarnings)

  return (
    <>
      {showPerformanceCard || (sections === "all" && showBestSetupCard) ? (
        <div className="grid grid-cols-1 gap-2 md:grid-cols-2 md:gap-3">
          {showPerformanceCard ? (
            <PerformanceInsightsCard
              totalTrades={totalTrades}
              hasTradingDayTimeSource={hasTradingDayTimeSource}
              insights={insights}
              insightBestSymbol={insightBestSymbol}
              insightBestSymbolAvg={insightBestSymbolAvg}
              insightBestWeekday={insightBestWeekday}
              insightBestWeekdayAvg={insightBestWeekdayAvg}
            />
          ) : null}

          {sections === "all" && showBestSetupCard ? (
            <BestSetupCard bestSetup={bestSetup} wide={!showInsights} />
          ) : null}
        </div>
      ) : null}

      {/* Mobile Records tab: Best Setup sits with narrative insights. */}
      {sections === "records" && showBestSetupCard ? (
        <div className="grid grid-cols-1 gap-2">
          <BestSetupCard bestSetup={bestSetup} />
        </div>
      ) : null}

      {showNarrativeRow ? (
        <div className="grid grid-cols-1 gap-2 md:grid-cols-2 md:gap-3">
          {showInsights ? (
            <div className={dashboardInsightCardClass}>
              <h3 className={dashboardInsightTitleClass}>Advanced Edge</h3>
              <p className={dashboardInsightHelperClass}>
                Strongest combined setup (pairs or triples, min. 3 trades). Same
                filters as above.
              </p>
              {combinedInsights.length > 0 ? (
                <div className="space-y-2">
                  {combinedInsights.map((text, index) => (
                    <p
                      key={`combo-${index}-${text.slice(0, 20)}`}
                      className={`${dashboardInsightBodyClass} font-semibold`}
                    >
                      ⭐ <PositiveInsightLine text={text} />
                    </p>
                  ))}
                </div>
              ) : (
                <p className={dashboardInsightEmptyClass}>
                  No qualifying combined setup yet. Need 3+ trades with consistent
                  session, symbol, and direction data.
                </p>
              )}
            </div>
          ) : null}

          {showWorstSetup ? (
            <div className={dashboardInsightCardClass}>
              <h3 className={dashboardInsightTitleClass}>Risk Insights</h3>
              <p className={dashboardInsightHelperClass}>
                Lowest-performing combined setup (same 3+ trade rule as Advanced
                Edge).
              </p>
              {worstInsight ? (
                <p className={`${dashboardInsightBodyClass} font-semibold`}>
                  ⚠️ <NegativeInsightLine text={worstInsight} />
                </p>
              ) : (
                <p className={dashboardInsightEmptyClass}>
                  No combined setup to rank yet, or filters removed too much data.
                </p>
              )}
            </div>
          ) : null}

          {showWarnings ? (
            <div className={`${dashboardInsightCardClass} md:col-span-2`}>
              <h3 className={dashboardInsightTitleClass}>Behavior Warnings</h3>
              <p className={dashboardInsightHelperClass}>
                Post–loss streak win rate (next 5 trades) and RR sample comparison.
              </p>
              {warnings.length > 0 ? (
                <div className="space-y-2">
                  {warnings.map((warning, index) => (
                    <p
                      key={`warn-${index}-${warning.slice(0, 16)}`}
                      className={dashboardInsightBodyClass}
                    >
                      🚨 <WarningInsightLine text={warning} />
                    </p>
                  ))}
                </div>
              ) : (
                <p className={dashboardInsightEmptyClass}>
                  No behavioral flags for the current trade set.
                </p>
              )}
            </div>
          ) : null}
        </div>
      ) : null}
    </>
  )
}

export default memo(DashboardInsights)
