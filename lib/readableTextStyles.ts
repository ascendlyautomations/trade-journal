/**
 * Readable text hierarchy for dark navy surfaces.
 * Matches Prop Firm Mode / Explore — prefer these over ad-hoc gray-500 / white/40.
 *
 * Primary → white | Secondary → gray-300 | Label / muted / placeholder → gray-400
 */
export const READABLE_PRIMARY_CLASS = "text-white"

/** Supporting body copy (still clearly readable). */
export const READABLE_SECONDARY_CLASS = "text-gray-300"

/** Field labels, quiet meta, and helpers (never use gray-500 on dark panels). */
export const READABLE_LABEL_CLASS = "text-gray-400"

/** Alias for helpers / captions — same contrast as labels. */
export const READABLE_HELPER_CLASS = "text-gray-400"

/** Placeholder utility for inputs/textareas on dark surfaces. */
export const READABLE_PLACEHOLDER_CLASS = "placeholder:text-gray-400"

/** Select empty/unselected value and chevrons. */
export const READABLE_PLACEHOLDER_TEXT_CLASS = "text-gray-400"

/** Disabled / inactive option text — muted but visible. */
export const READABLE_DISABLED_TEXT_CLASS = "text-gray-400"

/** Empty states and tertiary actions (prefer over faint white/opacity). */
export const READABLE_EMPTY_CLASS = "text-gray-400"

/** Compact field label used in Add Account, trade forms, etc. */
export const READABLE_FIELD_LABEL_CLASS = "text-xs text-gray-400"

/** Compact helper under a field. */
export const READABLE_FIELD_HELPER_CLASS = "mt-1 text-xs text-gray-400"

/** Widget / insight section titles (Prop Firm / Equity Curve). */
export const READABLE_SECTION_TITLE_CLASS = "text-blue-300"

/** Table header / metric label row on dark panels. */
export const READABLE_TABLE_HEADER_CLASS = "text-gray-400"

/** Default body text on dark glass/solid cards (inheritance fallback). */
export const READABLE_CARD_TEXT_CLASS = "text-gray-100"

/** Standard hairline on dark surfaces — prefer over border-white/5. */
export const READABLE_BORDER_CLASS = "border-white/10"

/** Slightly stronger hairline for inputs / secondary buttons. */
export const READABLE_BORDER_STRONG_CLASS = "border-white/15"

/** Quiet icons / chevrons on navy (matches labels). */
export const READABLE_ICON_CLASS = "text-gray-400"

/* —— Recharts hex tokens (Profile equity readability baseline) —— */
export const READABLE_CHART_TICK = "#cbd5e1"
export const READABLE_CHART_GRID = "#334155"
export const READABLE_CHART_TOOLTIP_BG = "#0f172a"
export const READABLE_CHART_TOOLTIP_BORDER = "1px solid rgba(255,255,255,0.12)"
export const READABLE_CHART_TOOLTIP_LABEL = "#cbd5e1"
export const READABLE_CHART_TOOLTIP_ITEM = "#ffffff"
