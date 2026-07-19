/** Shared vertical spacing for account dropdown menus (filter bar + picker). */

import {
  READABLE_DISABLED_TEXT_CLASS,
  READABLE_PRIMARY_CLASS,
} from "@/lib/readableTextStyles"

export const ACCOUNT_DROPDOWN_ROW_HEIGHT_CLASS = "flex min-h-9 items-center"

export const ACCOUNT_DROPDOWN_ROW_TEXT_CLASS =
  "min-w-0 flex-1 truncate whitespace-nowrap"

export const ACCOUNT_DROPDOWN_ITEM_CLASS =
  `${ACCOUNT_DROPDOWN_ROW_HEIGHT_CLASS} cursor-pointer px-3 py-2 text-sm ${READABLE_PRIMARY_CLASS} hover:bg-[#1f2937]`

export const ACCOUNT_DROPDOWN_DIVIDER_CLASS =
  `pointer-events-none select-none px-3 text-xs leading-none ${READABLE_DISABLED_TEXT_CLASS} max-md:overflow-hidden max-md:whitespace-nowrap`

export const ACCOUNT_DROPDOWN_MANAGE_CLASS =
  `${ACCOUNT_DROPDOWN_ROW_HEIGHT_CLASS} cursor-pointer px-3 py-2 text-sm text-white hover:bg-[#1f2937]`

/** Blue action row — Copy Trading entry only. */
export const ACCOUNT_DROPDOWN_ACTION_CLASS =
  `${ACCOUNT_DROPDOWN_ROW_HEIGHT_CLASS} cursor-pointer px-3 py-2 text-sm text-blue-400 hover:bg-[#1f2937]`

/** Desktop width for trigger + menu (dashboard, trades, input trade, quick trade). */
export const ACCOUNT_DROPDOWN_DESKTOP_WIDTH_CLASS =
  "md:min-w-[20rem] md:w-[20rem] md:shrink-0"

export const ACCOUNT_DROPDOWN_PANEL_CLASS =
  "absolute z-[110] mt-1 max-h-60 w-full max-md:w-max max-md:min-w-full max-md:max-w-[calc(100vw-1.5rem)] overflow-x-hidden overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"

/** Closed trigger — Input Trade / Quick Trade / submission surfaces. */
export const ACCOUNT_DROPDOWN_TRIGGER_CLASS =
  `flex w-full min-w-0 cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-left text-sm text-white transition-colors hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500/40 ${ACCOUNT_DROPDOWN_DESKTOP_WIDTH_CLASS}`

/** Filter-bar trigger — dashboard / trades. */
export const ACCOUNT_DROPDOWN_FILTER_TRIGGER_CLASS =
  `flex w-full min-w-0 cursor-pointer items-center justify-between h-[34px] rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-left text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 ${ACCOUNT_DROPDOWN_DESKTOP_WIDTH_CLASS}`

/** Outer wrapper for filter-mode picker in TradeFilterBar. */
export const ACCOUNT_DROPDOWN_FILTER_WRAPPER_CLASS =
  `w-full md:w-auto ${ACCOUNT_DROPDOWN_DESKTOP_WIDTH_CLASS}`

/** Outer wrapper for submission-mode picker (Input Trade, Quick Trade, /app). */
export const ACCOUNT_DROPDOWN_SUBMISSION_WRAPPER_CLASS =
  `w-full ${ACCOUNT_DROPDOWN_DESKTOP_WIDTH_CLASS}`

/** @deprecated Prefer ACCOUNT_DROPDOWN_FILTER_TRIGGER_CLASS */
export const ACCOUNT_DROPDOWN_TRIGGER_COMPACT_CLASS =
  ACCOUNT_DROPDOWN_FILTER_TRIGGER_CLASS

/**
 * Portaled menu shell — CustomSelect and other fixed-position menus.
 * Must sit above ScrollableModalShell (z-10050) / FeedbackModal (z-10060);
 * same layer as DropdownMenu (see modalLayout stacking notes).
 */
export const ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS =
  "fixed z-[10070] max-h-60 overflow-x-hidden overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"

export const ACCOUNT_DROPDOWN_OPTION_CLASS =
  "w-full px-3 py-2 text-left text-sm text-white focus:outline-none hover:bg-[#1f2937]"

export const ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS = "bg-[#1f2937] font-medium"

/**
 * Cross-browser form selects (CustomSelect). Same closed-state chrome as native
 * fields, without account-picker desktop width. Prefer these over raw <select>
 * so Safari does not apply OS-native control chrome.
 */
export const SELECT_TRIGGER_CLASS =
  "flex w-full min-w-0 cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-left text-sm text-white transition-colors hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500/40"

/** Compact pad — matches InputTradeForm / QuickTrade modal field height. */
export const SELECT_TRIGGER_COMPACT_CLASS =
  "flex w-full min-w-0 cursor-pointer items-center justify-between rounded border border-white/10 bg-[#0f172a] p-2 text-left text-sm text-white transition-colors hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500/40 lg:rounded-lg lg:p-2.5"

/** Filter-bar / toolbar selects — fixed 34px height, no forced desktop width. */
export const SELECT_FILTER_TRIGGER_CLASS =
  "flex h-[34px] w-full min-w-0 cursor-pointer items-center justify-between rounded-md border border-white/10 bg-[#0f172a] px-3 py-1 text-left text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500 md:w-auto md:shrink-0"

/** Admin / toolbar inline filters. */
export const SELECT_INLINE_TRIGGER_CLASS =
  "flex h-[34px] w-full min-w-0 cursor-pointer items-center justify-between rounded-md border border-white/10 bg-[#0f172a] px-3 py-1.5 text-left text-sm text-white hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500"

/** Create-account modal selects (emerald focus ring). */
export const SELECT_MODAL_TRIGGER_CLASS =
  "mt-1 flex w-full min-w-0 cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-left text-sm text-white focus:border-emerald-500/50 focus:outline-none focus:ring-1 focus:ring-emerald-500/30"

export const SELECT_MENU_CLASS = ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS
