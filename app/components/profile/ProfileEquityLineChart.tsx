"use client"

import { useSyncExternalStore } from "react"
import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"
import { chartTooltipStyles } from "@/lib/chartTheme"
import {
  DEFAULT_WEB_APPEARANCE,
  parseWebAppearance,
  WEB_APPEARANCE_CHANGE_EVENT,
  type WebAppearance,
} from "@/lib/webAppearance"

/** Y-axis dollar labels — light chart surface vs dark / OG navy surfaces. */
const PROFILE_EQUITY_Y_AXIS_TICK_FILL: Record<WebAppearance, string> = {
  light: "#64748b",
  dark: "var(--tt-chart-tick, #b8c4d2)",
  og: "#cbd5e1",
}

function readProfileEquityAppearance(): WebAppearance {
  if (typeof document === "undefined") return DEFAULT_WEB_APPEARANCE
  const attr = document.documentElement.getAttribute("data-tt-appearance")
  if (attr) return parseWebAppearance(attr)
  return DEFAULT_WEB_APPEARANCE
}

function subscribeProfileEquityAppearance(onStoreChange: () => void) {
  window.addEventListener(WEB_APPEARANCE_CHANGE_EVENT, onStoreChange)
  return () => window.removeEventListener(WEB_APPEARANCE_CHANGE_EVENT, onStoreChange)
}

export type ProfileEquityPoint = {
  index: number
  equity: number
}

type ProfileEquityLineChartProps = {
  data: ProfileEquityPoint[]
  narrow: boolean
}

export default function ProfileEquityLineChart({
  data,
  narrow,
}: ProfileEquityLineChartProps) {
  const appearance = useSyncExternalStore(
    subscribeProfileEquityAppearance,
    readProfileEquityAppearance,
    () => DEFAULT_WEB_APPEARANCE,
  )
  const yAxisTickFill = PROFILE_EQUITY_Y_AXIS_TICK_FILL[appearance]

  return (
    <ResponsiveContainer width="100%" height="100%">
      <LineChart
        data={data}
        margin={
          narrow
            ? { top: 12, right: 8, left: 4, bottom: 12 }
            : { top: 8, right: 16, left: 12, bottom: 8 }
        }
      >
        <CartesianGrid stroke="rgba(148, 163, 184, 0.08)" />
        <XAxis dataKey="index" hide />
        <YAxis
          width={narrow ? 50 : undefined}
          tickCount={narrow ? 5 : 7}
          axisLine={{
            stroke: "rgba(148, 163, 184, 0.1)",
          }}
          tickLine={{
            stroke: "rgba(148, 163, 184, 0.08)",
          }}
          tick={{
            fill: yAxisTickFill,
            fontSize: narrow ? 10 : 12,
          }}
          tickFormatter={(value) => {
            const n = Number(value)
            if (!Number.isFinite(n)) return "$0"
            if (n < 0) {
              return `-$${Math.abs(n).toLocaleString(undefined, {
                maximumFractionDigits: 2,
              })}`
            }
            return `$${n.toLocaleString(undefined, {
              maximumFractionDigits: 2,
            })}`
          }}
        />
        <Tooltip
          {...chartTooltipStyles}
          contentStyle={{
            ...chartTooltipStyles.contentStyle,
            borderRadius: "0.5rem",
          }}
          formatter={(value) => {
            const n = Number(value)
            if (!Number.isFinite(n)) return ["$0", "Equity"]
            const formatted =
              n < 0
                ? `-$${Math.abs(n).toLocaleString(undefined, {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}`
                : `$${n.toLocaleString(undefined, {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2,
                  })}`
            return [formatted, "Equity"]
          }}
        />
        <Line
          type="monotone"
          dataKey="equity"
          stroke="#22c55e"
          strokeWidth={narrow ? 2.5 : 2}
          dot={false}
        />
      </LineChart>
    </ResponsiveContainer>
  )
}
