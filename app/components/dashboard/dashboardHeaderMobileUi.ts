/** Mobile-only dashboard filter bar controls (desktop uses existing md: classes). */

/** Matches All Modes dropdown: h-[34px], rounded-md, text-sm. */
export const DASHBOARD_MOBILE_HEADER_CONTROL_CLASS =
  "inline-flex h-[34px] w-full min-w-0 items-center justify-center whitespace-nowrap rounded-md px-3 text-sm"

export const DASHBOARD_MOBILE_TIMEFRAME_BTN_CLASS = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} bg-white/10 font-medium text-white transition hover:bg-white/20`

export const DASHBOARD_MOBILE_PUBLIC_BTN_BASE = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} border transition`

export const DASHBOARD_MOBILE_ACTION_BTN_CLASS = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} bg-white/10 font-medium text-white transition hover:bg-white/20`

export const DASHBOARD_MOBILE_ICON_BTN_CLASS =
  "inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-md bg-white/10 text-base text-white transition hover:bg-white/20"

export const DASHBOARD_MOBILE_GEAR_BTN_CLASS =
  "inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-md bg-[#1f2937] text-white transition hover:bg-[#1f2937]/90"
