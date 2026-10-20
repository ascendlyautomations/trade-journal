"use client"

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  Legend,
  CartesianGrid,
  ResponsiveContainer,
  ReferenceLine,
} from "recharts"
import DashboardWidgetEmptyState from "@/app/components/dashboard/DashboardWidgetEmptyState"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"
import { READABLE_SECONDARY_CLASS } from "@/lib/readableTextStyles"
import { formatDashboardChartTooltipLabel } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"
import { formatProfitFactor } from "@/lib/formatDisplay"
import ChartWhenSized from "@/app/components/dashboard/ChartWhenSized"

export type EquityChartPoint = {
  date: string
  equity: number
  drawdownFloor?: number | null
}

export type DashboardEquityCurveProps = {
  data: EquityChartPoint[]
  variant: "mobile" | "desktop" | "hero"
  isPro?: boolean
  profitFactor?: number | null
  currentStreak?: number
  avgDay?: number
  consistency?: number
  totalTrades?: number
  /** Hero header context. Desktop terminal only. */
  timeframeLabel?: string
  /** @deprecated Flat reference — prefer `drawdownFloor` series on chart points. */
  drawdownLimitLineY?: number | null
  /** Live single-account balance curve (not cumulative P&L). */
  equityCurveUsesAccountBalance?: boolean
  /** Render personal drawdown floor from `drawdownFloor` on each point. */
  showPersonalDrawdownFloor?: boolean
}

const DRAWDOWN_LIMIT_LINE_LABEL = "Max Drawdown Limit"
const DRAWDOWN_FLOOR_LINE_LABEL = "Drawdown Floor"

function formatEquityTooltipValue(value: unknown): string {
  const n = Number(value)
  if (!Number.isFinite(n)) return "—"
  return n < 0
    ? `-$${Math.abs(n).toLocaleString()}`
    : `$${n.toLocaleString()}`
}

function equityTooltipFormatter(value: unknown, name: unknown): [string, string] {
  const key = String(name ?? "")
  const label =
    key === "drawdownFloor" ? DRAWDOWN_FLOOR_LINE_LABEL : "Equity"
  return [formatEquityTooltipValue(value), label]
}

function DrawdownLimitReferenceLine({ y }: { y: number }) {
  return (
    <ReferenceLine
      y={y}
      stroke="#ef4444"
      strokeDasharray="6 4"
      strokeWidth={1.5}
      ifOverflow="extendDomain"
      label={{
        value: DRAWDOWN_LIMIT_LINE_LABEL,
        position: "insideTopRight",
        fill: "#f87171",
        fontSize: 10,
      }}
    />
  )
}

function ChartEmptyState() {
  return (
    <DashboardWidgetEmptyState
      variant="no-trades"
      showImportCsv
      className="py-8"
    />
  )
}

export default function DashboardEquityCurve({
  data,
  variant,
  isPro = true,
  profitFactor = 0,
  currentStreak = 0,
  avgDay = 0,
  consistency = 0,
  totalTrades = 0,
  timeframeLabel,
  drawdownLimitLineY = null,
  equityCurveUsesAccountBalance = false,
  showPersonalDrawdownFloor = false,
}: DashboardEquityCurveProps) {
  const showEmpty =
    data.length === 0 ||
    (!equityCurveUsesAccountBalance && totalTrades === 0)
  const showDrawdownLimitLine =
    !showPersonalDrawdownFloor &&
    drawdownLimitLineY != null &&
    Number.isFinite(drawdownLimitLineY)
  const showFloorSeries =
    showPersonalDrawdownFloor &&
    data.some(
      (point) =>
        point.drawdownFloor != null && Number.isFinite(point.drawdownFloor)
    )

  if (variant === "mobile") {
    // Chart-first: no title. Keep chart height; tighten card chrome only.
    return (
      <div className="w-full block overflow-visible rounded-xl border border-white/10 bg-white/10 px-2 pb-1 pt-1.5 backdrop-blur-md md:hidden">
        {showEmpty ? (
          <ChartEmptyState />
        ) : (
        <ChartWhenSized height={268} className="w-full">
          <ResponsiveContainer width="100%" height={268}>
            <LineChart
              data={data}
              margin={{ top: 8, right: 8, left: 4, bottom: 4 }}
            >
              <CartesianGrid {...chartCartesianGridProps} />
              <XAxis
                dataKey="date"
                {...chartAxisTick(11)}
                tickFormatter={(value) => {
                  const d = new Date(String(value))
                  if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                  return `${d.getMonth() + 1}/${d.getDate()}`
                }}
                interval="preserveStartEnd"
                minTickGap={24}
                angle={-25}
                textAnchor="end"
                height={48}
              />
              <YAxis
                {...chartAxisTick(11)}
                tickFormatter={(value) =>
                  Number(value) < 0
                    ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 0,
                      })}`
                    : `$${Number(value).toLocaleString(undefined, {
                        minimumFractionDigits: 0,
                        maximumFractionDigits: 0,
                      })}`
                }
              />
              <Tooltip
                formatter={equityTooltipFormatter}
                labelFormatter={(label) => formatDashboardChartTooltipLabel(label)}
                {...chartTooltipStyles}
              />
              <Line
                type="monotone"
                dataKey="equity"
                name="equity"
                stroke="#22c55e"
                strokeWidth={2}
                dot={false}
              />
              {showFloorSeries ? (
                <Line
                  type="monotone"
                  dataKey="drawdownFloor"
                  name="drawdownFloor"
                  stroke="#ef4444"
                  strokeDasharray="6 4"
                  strokeWidth={1.5}
                  dot={false}
                  connectNulls
                />
              ) : null}
              {showDrawdownLimitLine ? (
                <DrawdownLimitReferenceLine y={drawdownLimitLineY} />
              ) : null}
            </LineChart>
          </ResponsiveContainer>
        </ChartWhenSized>
        )}
      </div>
    )
  }

  if (variant === "hero") {
    return (
      <div className="flex h-full min-h-0 flex-col">
        <div className="mb-3 flex items-baseline justify-between gap-3">
          <h2 className="tt-dash-section-title">Equity Curve</h2>
          <p className="tt-dash-section-subtitle">
            {[timeframeLabel, `${totalTrades.toLocaleString()} ${totalTrades === 1 ? "trade" : "trades"}`]
              .filter(Boolean)
              .join(" · ")}
          </p>
        </div>
        {showEmpty ? (
          <ChartEmptyState />
        ) : (
          <ChartWhenSized
            height={360}
            className="tt-dash-equity-plot rounded-lg bg-black/20"
          >
            <ResponsiveContainer width="100%" height={360}>
              <LineChart
                data={data}
                margin={{ top: 16, right: 12, left: 4, bottom: 8 }}
              >
                <CartesianGrid stroke="rgba(125,133,144,0.18)" vertical={false} />
                <XAxis
                  dataKey="date"
                  {...chartAxisTick(11)}
                  tickFormatter={(value) => {
                    const d = new Date(String(value))
                    if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                    return `${d.getMonth() + 1}/${d.getDate()}`
                  }}
                  interval="preserveStartEnd"
                  minTickGap={28}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  {...chartAxisTick(11)}
                  width={56}
                  axisLine={false}
                  tickLine={false}
                  tickFormatter={(value) =>
                    Number(value) < 0
                      ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                          maximumFractionDigits: 0,
                        })}`
                      : `$${Number(value).toLocaleString(undefined, {
                          maximumFractionDigits: 0,
                        })}`
                  }
                />
                <Tooltip
                  formatter={equityTooltipFormatter}
                  labelFormatter={(label) =>
                    formatDashboardChartTooltipLabel(label)
                  }
                  {...chartTooltipStyles}
                />
                <Line
                  type="monotone"
                  dataKey="equity"
                  name="equity"
                  stroke="#38bdf8"
                  strokeWidth={2.5}
                  dot={false}
                  activeDot={{ r: 3, strokeWidth: 0 }}
                />
                {showFloorSeries ? (
                  <Line
                    type="monotone"
                    dataKey="drawdownFloor"
                    name="drawdownFloor"
                    stroke="#ef4444"
                    strokeDasharray="6 4"
                    strokeWidth={1.5}
                    dot={false}
                    connectNulls
                  />
                ) : null}
                {showDrawdownLimitLine ? (
                  <DrawdownLimitReferenceLine y={drawdownLimitLineY} />
                ) : null}
              </LineChart>
            </ResponsiveContainer>
          </ChartWhenSized>
        )}
      </div>
    )
  }

  return (
    <div className="hidden md:block overflow-visible rounded-xl border border-white/10 bg-white/10 p-3 md:p-4 backdrop-blur-md">
      <h2 className="text-sm md:text-base font-semibold mb-3 text-blue-300">
        Equity Curve
      </h2>

      {showEmpty ? (
        <ChartEmptyState />
      ) : (
      <>
      <ChartWhenSized height={300} className="w-full">
        <ResponsiveContainer width="100%" height={300}>
          <LineChart
            data={data}
            margin={{ top: 10, right: 20, left: 20, bottom: 20 }}
          >
            <CartesianGrid {...chartCartesianGridProps} />
            <XAxis
              dataKey="date"
              {...chartAxisTick(12)}
              tickFormatter={(value) => {
                const d = new Date(String(value))
                if (Number.isNaN(d.getTime())) return String(value).slice(0, 10)
                return `${d.getMonth() + 1}/${d.getDate()}`
              }}
              interval="preserveStartEnd"
              minTickGap={24}
              angle={-25}
              textAnchor="end"
              height={48}
            />
            <YAxis
              {...chartAxisTick(12)}
              tickFormatter={(value) =>
                Number(value) < 0
                  ? `-$${Math.abs(Number(value)).toLocaleString(undefined, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 0,
                    })}`
                  : `$${Number(value).toLocaleString(undefined, {
                      minimumFractionDigits: 0,
                      maximumFractionDigits: 0,
                    })}`
              }
            />
            <Tooltip
              formatter={equityTooltipFormatter}
              labelFormatter={(label) =>
                formatDashboardChartTooltipLabel(label)
              }
              {...chartTooltipStyles}
            />
            <Legend
              wrapperStyle={{ paddingTop: 8 }}
              formatter={(value) => (
                <span className={`text-xs ${READABLE_SECONDARY_CLASS}`}>
                  {String(value) === "drawdownFloor"
                    ? DRAWDOWN_FLOOR_LINE_LABEL
                    : "Equity"}
                </span>
              )}
            />
            <Line
              type="monotone"
              dataKey="equity"
              name="equity"
              stroke="#22c55e"
              strokeWidth={2}
              dot={false}
            />
            {showFloorSeries ? (
              <Line
                type="monotone"
                dataKey="drawdownFloor"
                name="drawdownFloor"
                stroke="#ef4444"
                strokeDasharray="6 4"
                strokeWidth={1.5}
                dot={false}
                connectNulls
              />
            ) : null}
            {showDrawdownLimitLine ? (
              <DrawdownLimitReferenceLine y={drawdownLimitLineY} />
            ) : null}
          </LineChart>
        </ResponsiveContainer>
      </ChartWhenSized>

      {isPro ? (
      <div className="flex flex-wrap gap-3 mt-4">
        <div
          className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
            profitFactor == null
              ? "text-white bg-white/5 border border-white/10"
              : profitFactor >= 1
                ? "text-green-400 bg-green-500/10 border border-green-500/20"
                : "text-red-400 bg-red-500/10 border border-red-500/20"
          }`}
        >
          Profit Factor: {formatProfitFactor(profitFactor)}
        </div>

        <div
          className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
            currentStreak > 0
              ? "text-green-400 bg-green-500/10 border border-green-500/20"
              : "text-red-400 bg-red-500/10 border border-red-500/20"
          }`}
        >
          Streak:{" "}
          {currentStreak > 0
            ? `${currentStreak} Wins`
            : `${Math.abs(currentStreak)} Losses`}
        </div>

        <div
          className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
            avgDay > 0
              ? "text-green-400 bg-green-500/10 border border-green-500/20"
              : avgDay < 0
                ? "text-red-400 bg-red-500/10 border border-red-500/20"
                : "text-gray-300 bg-white/10 border border-white/10"
          }`}
        >
          Avg Day: {formatCurrency(avgDay)}
        </div>

        <div
          className={`px-3 py-2 rounded-lg text-sm font-medium backdrop-blur-md transition-all duration-200 hover:scale-[1.03] ${
            consistency >= 60
              ? "text-green-400 bg-green-500/10 border border-green-500/20"
              : consistency >= 30
                ? "text-yellow-400 bg-yellow-500/10 border border-yellow-500/20"
                : "text-red-400 bg-red-500/10 border border-red-500/20"
          }`}
        >
          Consistency: {consistency.toFixed(0)}%
        </div>
      </div>
      ) : null}
      </>
      )}
    </div>
  )
}
