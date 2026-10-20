/**
 * Shared Recharts theme for dark navy surfaces.
 * Tick/label colors use `--tt-chart-tick` / `--tt-text-muted` on authenticated dark/light.
 * Aligns with Prop Firm / Explore text hierarchy without inventing new palette hues.
 */

import {
  READABLE_CHART_GRID,
  READABLE_CHART_TICK,
  READABLE_CHART_TOOLTIP_BG,
  READABLE_CHART_TOOLTIP_BORDER,
  READABLE_CHART_TOOLTIP_ITEM,
  READABLE_CHART_TOOLTIP_LABEL,
} from "@/lib/readableTextStyles"

export {
  READABLE_CHART_GRID,
  READABLE_CHART_TICK,
  READABLE_CHART_TOOLTIP_BG,
  READABLE_CHART_TOOLTIP_BORDER,
  READABLE_CHART_TOOLTIP_ITEM,
  READABLE_CHART_TOOLTIP_LABEL,
}

/** Axis stroke + tick fill for XAxis / YAxis. */
export function chartAxisTick(fontSize: number) {
  return {
    stroke: "var(--tt-chart-grid, #334155)",
    tick: { fill: "var(--tt-chart-tick, #cbd5e1)", fontSize },
  }
}

/** Shared dark tooltip chrome for Recharts Tooltip. */
export const chartTooltipStyles = {
  contentStyle: {
    backgroundColor: READABLE_CHART_TOOLTIP_BG,
    border: READABLE_CHART_TOOLTIP_BORDER,
    borderRadius: "8px",
  },
  labelStyle: { color: READABLE_CHART_TOOLTIP_LABEL },
  itemStyle: { color: READABLE_CHART_TOOLTIP_ITEM },
} as const

export const chartCartesianGridProps = {
  stroke: "var(--tt-chart-grid, #334155)",
} as const
