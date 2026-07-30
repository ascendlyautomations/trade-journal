/**
 * Mobile-only INTERNAL card padding (max-md).
 * Do not use these for section-to-section gaps or chart heights.
 */

/** Filter bar inner padding only. */
export const DASHBOARD_MOBILE_FILTER_SHELL_CLASS =
  "max-md:gap-2.5 max-md:px-2 max-md:py-2"

/** Card chrome: reduce empty pad around content; keep chart heights untouched. */
export const DASHBOARD_MOBILE_CARD_PAD_CLASS =
  "max-md:px-2.5 max-md:pb-1 max-md:pt-2"

export const DASHBOARD_MOBILE_CARD_TITLE_CLASS = "max-md:mb-1"

/** Metric cards: same footprint; slightly tighter padding for 3-col mobile. */
export const DASHBOARD_MOBILE_STAT_PAD_CLASS = "max-md:px-1.5 max-md:py-2"
