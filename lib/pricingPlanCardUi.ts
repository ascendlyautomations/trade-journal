/**
 * Typography + spacing for pricing / plan comparison cards.
 * Tightens feature lists without changing card layout, colors, or controls.
 */

/** Plan description under the price — slightly smaller than body copy. */
export const PRICING_CARD_PLAN_DESCRIPTION =
  "mt-3 text-[13px] leading-snug text-gray-400 md:text-sm md:leading-relaxed"

export const PRICING_CARD_PRO_PLAN_DESCRIPTION =
  "mt-3 text-[13px] leading-snug text-gray-300 md:text-sm md:leading-relaxed"

export const PRICING_CARD_PRO_PLAN_DESCRIPTION_LIGHT =
  "mt-3 text-[13px] leading-snug text-gray-200 md:text-sm md:leading-relaxed"

/** Label above the Pro incremental feature list. */
export const PRICING_CARD_PRO_FEATURES_HEADING =
  "mt-4 text-xs font-medium text-gray-200 md:mt-5 md:text-[13px]"

export const PRICING_CARD_PRO_FEATURES_HEADING_ALT =
  "mt-3 text-xs font-medium text-gray-100 md:mt-4 md:text-[13px]"

/** Subheading for grouped Pro feature sections inside pricing cards. */
export const PRICING_CARD_PRO_FEATURE_GROUP_HEADING =
  "mt-3 text-[11px] font-semibold uppercase tracking-wide text-teal-300/90 first:mt-2 md:mt-3.5 md:text-xs"

export const PRICING_CARD_PRO_FEATURE_GROUP_HEADING_LANDING =
  "mt-3 text-[11px] font-semibold uppercase tracking-wide text-emerald-300/90 first:mt-2 md:mt-3.5 md:text-xs"

/** Compact feature list — Pro cards use the tighter gap. */
export const PRICING_CARD_FEATURE_LIST =
  "mt-6 flex flex-1 flex-col gap-2 text-left text-xs text-gray-300 md:mt-7 md:gap-2.5 md:text-[13px]"

export const PRICING_CARD_PRO_FEATURE_LIST =
  "mt-2 flex flex-1 flex-col gap-1.5 text-left text-xs text-gray-100 md:gap-2 md:text-[13px]"

export const PRICING_CARD_FEATURE_ITEM = "flex gap-2 md:gap-2.5"

export const PRICING_CARD_FEATURE_TEXT = "leading-snug"

/** Pricing page — compact primary trial CTA (Pro card). */
export const PRICING_PAGE_PRIMARY_CTA =
  "mt-4 w-full rounded-xl bg-blue-500 py-3 text-center text-[15px] font-bold text-white shadow-lg transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500 sm:py-3.5 sm:text-base"

/** Fine print directly under the trial CTA. */
export const PRICING_PAGE_CTA_FINE_PRINT =
  "mt-2.5 text-center text-[11px] leading-snug text-gray-300 sm:text-xs"

/** "Why TradeTraxs Pro?" value bullets — pricing page. */
export const PRICING_PAGE_WHY_PRO_BULLETS = [
  "Unlimited trades and trading accounts",
  "AI Analyst and weekly & monthly trading reports",
  "Premium analytics and performance insights",
  "Backtest Lab and Prop Firm Mode",
  "Performance image exports for sharing your results",
  "Full social experience included on every plan",
] as const

export const PRICING_PAGE_WHY_PRO_LIST =
  "mt-6 grid grid-cols-1 gap-3 text-left text-sm text-gray-200 sm:gap-3.5 md:mt-8 md:grid-cols-2 md:gap-x-10 md:gap-y-3.5 md:text-[15px]"

export const PRICING_PAGE_WHY_PRO_ITEM = "flex gap-3"
