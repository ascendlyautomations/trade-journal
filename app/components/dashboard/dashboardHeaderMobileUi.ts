/** Mobile-only dashboard filter bar controls (desktop uses existing md: classes). */

/** Phone compact control. Desktop restores auto height so 34px cannot leak ≥768. */
export const DASHBOARD_MOBILE_HEADER_CONTROL_CLASS =
  "tt-mobile-web-hit-y inline-flex w-full min-w-0 items-center justify-center whitespace-nowrap rounded-md px-3 text-sm max-md:h-[34px] md:h-auto md:py-2"

export const DASHBOARD_MOBILE_TIMEFRAME_BTN_CLASS = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} bg-white/10 font-medium text-white transition hover:bg-white/20`

export const DASHBOARD_MOBILE_PUBLIC_BTN_BASE = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} border transition`

export const DASHBOARD_MOBILE_ACTION_BTN_CLASS = `${DASHBOARD_MOBILE_HEADER_CONTROL_CLASS} bg-white/10 font-medium text-white transition hover:bg-white/20`

export const DASHBOARD_MOBILE_ICON_BTN_CLASS =
  "tt-mobile-web-hit inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-md bg-white/10 text-base text-white transition hover:bg-white/20"

export const DASHBOARD_MOBILE_GEAR_BTN_CLASS =
  "tt-mobile-web-hit inline-flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-md bg-white/10 text-white transition hover:bg-white/20"
