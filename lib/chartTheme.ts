/**
 * Shared Recharts theme for dark navy surfaces.
 * Tick/label colors match Profile equity (`#cbd5e1` ≈ gray-300) — clearer than slate-400.
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
    stroke: READABLE_CHART_TICK,
    tick: { fill: READABLE_CHART_TICK, fontSize },
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
  stroke: READABLE_CHART_GRID,
} as const
