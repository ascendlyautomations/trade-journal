/** Shared vertical spacing for account dropdown menus (filter bar + picker). */

export const ACCOUNT_DROPDOWN_ITEM_CLASS =
  "cursor-pointer px-3 py-2 text-sm text-white hover:bg-[#1f2937] max-md:truncate max-md:whitespace-nowrap"

export const ACCOUNT_DROPDOWN_DIVIDER_CLASS =
  "pointer-events-none select-none px-3 text-xs leading-none text-gray-500 max-md:overflow-hidden max-md:whitespace-nowrap"

export const ACCOUNT_DROPDOWN_MANAGE_CLASS =
  "cursor-pointer px-3 py-2 text-sm text-white hover:bg-[#1f2937]"

export const ACCOUNT_DROPDOWN_PANEL_CLASS =
  "absolute z-[110] mt-1 max-h-60 w-full max-md:w-max max-md:min-w-full max-md:max-w-[calc(100vw-1.5rem)] overflow-x-hidden overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"

/** Closed trigger — Input Trade account picker. */
export const ACCOUNT_DROPDOWN_TRIGGER_CLASS =
  "flex w-full cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-[#0f172a] p-2.5 text-left text-sm text-white transition-colors hover:bg-[#1e293b] focus:outline-none focus:ring-2 focus:ring-blue-500/40"

/** Compact closed trigger — analytics / filter surfaces. */
export const ACCOUNT_DROPDOWN_TRIGGER_COMPACT_CLASS =
  "flex h-9 w-full cursor-pointer items-center justify-between rounded-lg border border-white/10 bg-black/30 px-3 py-1.5 text-sm text-white transition-colors hover:bg-white/5 focus:outline-none focus:ring-2 focus:ring-blue-500/40"

/** Portaled menu shell — CustomSelect and other fixed-position menus. */
export const ACCOUNT_DROPDOWN_PORTAL_MENU_CLASS =
  "fixed z-[1500] max-h-60 overflow-x-hidden overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"

export const ACCOUNT_DROPDOWN_OPTION_CLASS =
  "w-full px-3 py-2 text-left text-sm text-white focus:outline-none hover:bg-[#1f2937]"

export const ACCOUNT_DROPDOWN_OPTION_SELECTED_CLASS = "bg-[#1f2937] font-medium"
