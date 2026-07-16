/** Shared typography for dashboard insight cards (Performance, Strategy, Edge, Risk, Warnings). */

import {
  READABLE_EMPTY_CLASS,
  READABLE_HELPER_CLASS,
  READABLE_LABEL_CLASS,
  READABLE_PRIMARY_CLASS,
  READABLE_SECONDARY_CLASS,
  READABLE_SECTION_TITLE_CLASS,
} from "@/lib/readableTextStyles"

export const dashboardInsightCardClass =
  "rounded-xl border border-white/10 bg-white/10 p-2.5 md:p-4 backdrop-blur-md"

/** Card / widget titles — same blue section accent as Equity Curve / Prop Firm. */
export const dashboardInsightTitleClass = `mb-1.5 md:mb-2 text-[11px] md:text-sm font-semibold ${READABLE_SECTION_TITLE_CLASS}`

export const dashboardInsightHelperClass = `mb-2 md:mb-3 text-[11px] md:text-sm leading-relaxed ${READABLE_SECONDARY_CLASS}`

export const dashboardInsightBodyClass = `text-[11px] md:text-sm ${READABLE_SECONDARY_CLASS}`

export const dashboardInsightEmptyClass = `text-[11px] md:text-sm ${READABLE_EMPTY_CLASS}`

export const dashboardInsightLabelClass = READABLE_LABEL_CLASS

export const dashboardInsightMetricValueClass =
  "text-[11px] md:text-sm font-semibold"

export const dashboardInsightMetricPositiveClass =
  "text-[11px] md:text-sm font-semibold text-green-400"

export const dashboardInsightMetricNegativeClass =
  "text-[11px] md:text-sm font-semibold text-red-400"

export const dashboardInsightMetricNeutralClass = `text-[11px] md:text-sm font-semibold ${READABLE_PRIMARY_CLASS}`

/** Compact widget subsection label (e.g. Trades by Session). */
export const dashboardWidgetSubtitleClass = `mb-1.5 text-[11px] md:mb-2 md:text-sm ${READABLE_HELPER_CLASS}`

/** Stat card metric title under a value. */
export const dashboardStatLabelClass = `mb-0.5 text-[11px] md:mb-1 md:text-sm ${READABLE_LABEL_CLASS}`

/** Card section heading inside a widget (Streaks, Trading Hours, …). */
export const dashboardWidgetSectionTitleClass = `mb-1.5 text-[11px] font-semibold md:mb-2 md:text-sm ${READABLE_SECTION_TITLE_CLASS}`
