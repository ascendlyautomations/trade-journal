"use client"

import {
  CartesianGrid,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts"

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
            fill: "#cbd5e1",
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
          contentStyle={{
            backgroundColor: "#0f172a",
            border: "1px solid rgba(255,255,255,0.12)",
            borderRadius: "0.5rem",
          }}
          labelStyle={{ color: "#cbd5e1" }}
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
