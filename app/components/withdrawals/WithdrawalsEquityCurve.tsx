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
import ChartWhenSized from "@/app/components/dashboard/ChartWhenSized"
import {
  chartAxisTick,
  chartCartesianGridProps,
  chartTooltipStyles,
} from "@/lib/chartTheme"
import { formatDashboardChartTooltipLabel } from "@/lib/formatEST"
import { formatCurrency } from "@/lib/formatCurrency"
import type { WithdrawalCumulativeChartPoint } from "@/lib/withdrawalsPresentation"

type WithdrawalsEquityCurveProps = {
  data: WithdrawalCumulativeChartPoint[]
  totalWithdrawn: number
}

function formatAxisMoney(value: unknown): string {
  const n = Number(value)
  if (!Number.isFinite(n)) return "—"
  return n < 0
    ? `-$${Math.abs(n).toLocaleString(undefined, { maximumFractionDigits: 0 })}`
    : `$${n.toLocaleString(undefined, { maximumFractionDigits: 0 })}`
}

export default function WithdrawalsEquityCurve({
  data,
  totalWithdrawn,
}: WithdrawalsEquityCurveProps) {
  const showEmpty = data.length <= 1

  return (
    <section className="rounded-xl border border-white/10 bg-white/10 p-3 backdrop-blur-md md:p-4">
      <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="text-sm font-semibold text-blue-300 md:text-base">
          Cumulative withdrawals
        </h2>
        <p className="text-xs text-gray-400 md:text-sm">
          Total withdrawn{" "}
          <span className="font-semibold tabular-nums text-white">
            {formatCurrency(totalWithdrawn)}
          </span>
        </p>
      </div>

      {showEmpty ? (
        <p className="py-10 text-center text-sm text-gray-400">
          Record withdrawals to see your cumulative payout curve.
        </p>
      ) : (
        <ChartWhenSized height={280} className="w-full">
          <ResponsiveContainer width="100%" height={280}>
            <LineChart
              data={data}
              margin={{ top: 10, right: 16, left: 8, bottom: 20 }}
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
                tickFormatter={formatAxisMoney}
                domain={[0, "auto"]}
              />
              <Tooltip
                {...chartTooltipStyles}
                labelFormatter={(label) => formatDashboardChartTooltipLabel(label)}
                formatter={(value, _name, payload) => {
                  const row = payload?.payload as
                    | WithdrawalCumulativeChartPoint
                    | undefined
                  if (!row) return [formatCurrency(Number(value)), "Cumulative"]
                  if (row.stepAmount <= 0) {
                    return [formatCurrency(0), "Starting balance"]
                  }
                  return [
                    `${formatCurrency(row.stepAmount)} withdrawal · ${formatCurrency(row.cumulative)} total`,
                    "Withdrawal",
                  ]
                }}
              />
              <Line
                type="monotone"
                dataKey="cumulative"
                name="cumulative"
                stroke="#22c55e"
                strokeWidth={2}
                dot={false}
                activeDot={{ r: 3, strokeWidth: 0 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </ChartWhenSized>
      )}
    </section>
  )
}
