/**
 * Mobile dashboard spacing + internal padding tokens.
 *
 * SECTION GAP STANDARD (between sections / cards): **8px = Tailwind `gap-2` / `mb-2`**.
 * Defined by filter bar → top metrics (`DASHBOARD_MOBILE_FILTER_MARGIN_CLASS`).
 *
 * Vertical stack parents should use a SINGLE `gap-2` (or `space-y-2`) — never
 * nest empty siblings that add a second gap between major sections.
 *
 * Do NOT use these for INTERNAL card padding (see PAD classes below).
 */

/** 8px — single mobile rhythm for stacks, grids, and section gaps. */
export const DASHBOARD_MOBILE_GAP_CLASS = "max-md:gap-2"

/** space-y equivalent of the section gap. */
export const DASHBOARD_MOBILE_SPACE_Y_CLASS = "max-md:space-y-2"

/** Filter bar → metrics margin (defines the standard: 8px / gap-2). */
export const DASHBOARD_MOBILE_FILTER_MARGIN_CLASS =
  "mt-0 mb-2 md:mt-2.5 md:mb-3"

/** Filter bar inner padding only. */
export const DASHBOARD_MOBILE_FILTER_SHELL_CLASS =
  "max-md:gap-2.5 max-md:px-2 max-md:py-2"

/** Card chrome: reduce empty pad around content; keep chart heights untouched. */
export const DASHBOARD_MOBILE_CARD_PAD_CLASS =
  "max-md:px-2.5 max-md:pb-1 max-md:pt-2"

export const DASHBOARD_MOBILE_CARD_TITLE_CLASS = "max-md:mb-1"

/** Metric cards: compact vertical density on mobile (keep width / tap target). */
export const DASHBOARD_MOBILE_STAT_PAD_CLASS =
  "max-md:min-h-[44px] max-md:px-1 max-md:py-[5px]"
