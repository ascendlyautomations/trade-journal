import {
  READABLE_FIELD_LABEL_CLASS,
  READABLE_HELPER_CLASS,
  READABLE_LABEL_CLASS,
  READABLE_PLACEHOLDER_CLASS,
  READABLE_PRIMARY_CLASS,
  READABLE_SECONDARY_CLASS,
} from "@/lib/readableTextStyles"

/** Shared field label styling for trade entry forms (Prop Firm / Explore hierarchy). */
export const TRADE_FIELD_LABEL_CLASS = `block ${READABLE_FIELD_LABEL_CLASS} mb-1`

/** Helper / hint under a trade form field. */
export const TRADE_FIELD_HELPER_CLASS = `mt-1 text-xs ${READABLE_HELPER_CLASS}`

/** Dark-surface input value + placeholder. */
export const TRADE_FIELD_INPUT_TEXT_CLASS = `${READABLE_PRIMARY_CLASS} ${READABLE_PLACEHOLDER_CLASS}`

/**
 * Standard Add Trade text/number control on navy surfaces.
 * Use for Symbol, Strategy, RR, Points, Contracts, etc.
 */
export const TRADE_FIELD_CONTROL_CLASS = `w-full p-2 rounded bg-[#0f172a] border border-white/10 ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Larger-pad control (psychology / custom timeframe on lg). */
export const TRADE_FIELD_CONTROL_LG_CLASS = `w-full p-2 lg:p-2.5 rounded bg-[#0f172a] border border-white/10 ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Currency fields ($ prefix + focus ring). */
export const TRADE_FIELD_CURRENCY_CONTROL_CLASS = `w-full pl-8 pr-3 py-2 rounded bg-[#0f172a] border border-white/10 focus:border-green-500 outline-none ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Compact textarea (confluences / psychology notes). */
export const TRADE_FIELD_TEXTAREA_CLASS = `w-full p-2 lg:p-2.5 h-20 lg:h-24 rounded bg-[#0f172a] border border-white/10 ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Public description — slightly taller, blue focus ring. */
export const TRADE_FIELD_PUBLIC_NOTES_CLASS = `w-full p-2 lg:p-2.5 rounded-lg bg-[#0f172a] border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500 min-h-[80px] lg:min-h-[96px] ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Column section title (Trade / Execution / Psychology). */
export const TRADE_FIELD_SECTION_TITLE_CLASS = `mb-2 text-sm ${READABLE_LABEL_CLASS}`

/** Checkbox / inline secondary labels on the form. */
export const TRADE_FIELD_CHECKBOX_LABEL_CLASS = `flex items-center gap-2 text-sm ${READABLE_SECONDARY_CLASS}`

/** Optional attachment labels (screenshot, reel) — identical typography and spacing. */
export const TRADE_OPTIONAL_ATTACHMENT_LABEL_CLASS = TRADE_FIELD_LABEL_CLASS

/** Full Input Trade — compact screenshot/reel click + drag upload zones. */
export const TRADE_FULL_INPUT_MEDIA_UPLOAD_CLASS =
  `mt-2 h-16 w-full flex cursor-pointer items-center justify-center rounded border border-dashed border-white/10 bg-transparent px-3 py-2 text-sm ${READABLE_HELPER_CLASS} transition hover:bg-white/5 disabled:cursor-not-allowed disabled:opacity-50`

/**
 * Quick Trade modal field chrome — same readable text/placeholder as Add Trade.
 * Keeps Quick Trade height / focus ring; does not change layout.
 */
export const QUICK_TRADE_INPUT_CLASS = `h-12 w-full rounded-lg border border-white/15 bg-[#0a1329] px-3 text-base outline-none transition focus:border-blue-400/60 focus:ring-2 focus:ring-blue-500/20 ${TRADE_FIELD_INPUT_TEXT_CLASS}`

/** Quick Trade labels — Prop Firm label contrast with slight weight. */
export const QUICK_TRADE_LABEL_CLASS = `block text-xs font-medium ${READABLE_LABEL_CLASS}`

