"use client"

import { useMemo, useState } from "react"
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import CustomSelect from "@/app/components/CustomSelect"
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import ChartWhenSized from "@/app/components/dashboard/ChartWhenSized"
import {
  buildStrategyComparisonChartData,
  type BacktestLabComparisonMetric,
  type BacktestLabGroupStats,
} from "@/lib/backtestLabAnalytics"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"
import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import { BACKTEST_LAB_SELECT_PROPS } from "@/lib/backtestLabUiStyles"

const METRIC_OPTIONS: { label: string; value: BacktestLabComparisonMetric }[] = [
  { label: "Net P&L", value: "netPnl" },
  { label: "Win rate", value: "winRate" },
  { label: "Profit factor", value: "profitFactor" },
  { label: "Average R", value: "avgRR" },
  { label: "Expectancy", value: "expectancy" },
]

function formatTooltipValue(metric: BacktestLabComparisonMetric, value: number): string {
  switch (metric) {
    case "netPnl":
    case "expectancy":
      return formatPnlCurrency(value, {
        minimumFractionDigits: 0,
        maximumFractionDigits: 2,
      })
    case "winRate":
      return `${value.toFixed(1)}%`
    case "profitFactor":
      return value >= 999 ? "∞" : value.toFixed(2)
    case "avgRR":
      return formatRR(value)
    default:
      return String(value)
  }
}

function yAxisTick(metric: BacktestLabComparisonMetric, value: number): string {
  if (metric === "netPnl" || metric === "expectancy") {
    const n = Number(value)
    if (n < 0) return `-$${Math.abs(n).toLocaleString()}`
    return `$${n.toLocaleString()}`
  }
  if (metric === "winRate") return `${value}%`
  if (metric === "profitFactor") return value >= 999 ? "∞" : Number(value).toFixed(1)
  if (metric === "avgRR") return formatRR(value)
  return String(value)
}

export type BacktestLabStrategyComparisonChartProps = {
  strategyRows: BacktestLabGroupStats[]
}

export default function BacktestLabStrategyComparisonChart({
  strategyRows,
}: BacktestLabStrategyComparisonChartProps) {
  const [metric, setMetric] = useState<BacktestLabComparisonMetric>("netPnl")

  const chartData = useMemo(
    () => buildStrategyComparisonChartData(strategyRows, metric),
    [strategyRows, metric]
  )

  const showEmpty = strategyRows.length === 0

  return (
    <section className="mb-6">
      <div className="mb-3 flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h2 className="text-xl font-semibold text-white">Strategy comparison</h2>
          <p className="text-sm text-gray-400">
            Top strategies by net P&L in your current filters (strategy filter not applied).
          </p>
        </div>
        <CustomSelect
          value={metric}
          onChange={(value) => setMetric(value as BacktestLabComparisonMetric)}
          {...BACKTEST_LAB_SELECT_PROPS}
          className="w-full sm:w-48"
          options={METRIC_OPTIONS}
        />
      </div>

      <div className="rounded-xl border border-white/10 bg-white/10 p-3 backdrop-blur-md md:p-4">
        {showEmpty ? (
          <DashboardWidgetEmptyState
            variant="no-trades"
            showImportCsv={false}
            className="py-8"
          />
        ) : chartData.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-400">
            Not enough data to chart this metric for the selected strategies.
          </p>
        ) : (
          <ChartWhenSized height={280} className="w-full">
            <ResponsiveContainer width="100%" height={280}>
              <BarChart
                data={chartData}
                margin={{ top: 8, right: 12, left: 4, bottom: 48 }}
              >
                <CartesianGrid {...chartCartesianGridProps} />
                <XAxis
                  dataKey="name"
                  {...chartAxisTick(11)}
                  interval={0}
                  angle={-28}
                  textAnchor="end"
                  height={56}
                />
                <YAxis
                  {...chartAxisTick(11)}
                  tickFormatter={(value) => yAxisTick(metric, Number(value))}
                />
                <Tooltip
                  formatter={(value) =>
                    formatTooltipValue(metric, Number(value))
                  }
                  labelFormatter={(label) => String(label)}
                  {...chartTooltipStyles}
                />
                <Bar dataKey="value" radius={[4, 4, 0, 0]}>
                  {chartData.map((entry) => (
                    <Cell
                      key={entry.key}
                      fill={
                        metric === "netPnl" || metric === "expectancy"
                          ? entry.value >= 0
                            ? "#34d399"
                            : "#f87171"
                          : "#38bdf8"
                      }
                    />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </ChartWhenSized>
        )}
      </div>
    </section>
  )
}
