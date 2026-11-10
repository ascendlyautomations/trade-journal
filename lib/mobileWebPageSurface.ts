/** Phone-only page background: drop the marketing gradient, keep desktop identical. */
export const MOBILE_WEB_NEUTRAL_PAGE_BG =
  "max-md:bg-none max-md:bg-[var(--tt-surface)]"

/** Phase-1 social pages (feed, notifications): neutral phone shell, desktop gradient unchanged. */
export const MOBILE_WEB_SOCIAL_PAGE_SHELL = `max-md:bg-[var(--tt-surface)] max-md:text-[color:var(--tt-text,#f0f3f6)]`

/** Full-bleed Experience screen shell (native Explore parity). */
export const MOBILE_WEB_EXPERIENCE_PAGE =
  "flex min-h-[var(--app-viewport-height)] flex-col bg-[color:var(--tt-surface,#0d1117)] text-[color:var(--tt-text,#f0f3f6)] md:hidden"

/** iOS-style rounded search field under the navbar title. */
export const MOBILE_WEB_EXPERIENCE_SEARCH =
  "h-11 w-full rounded-[10px] border border-[color:color-mix(in_srgb,var(--tt-text)_12%,transparent)] bg-[color:var(--tt-surface-nested,#1a222c)] px-3 text-base text-[color:var(--tt-text,#f0f3f6)] placeholder:text-[color:var(--tt-text-tertiary,#a8b3c2)] focus:border-[color:var(--tt-accent,#4ec4e0)] focus:outline-none focus:ring-2 focus:ring-[color:color-mix(in_srgb,var(--tt-accent,#4ec4e0)_35%,transparent)]"

/** Compact in-flow padding under the Phase 3A Navbar. */
export const MOBILE_WEB_PAGE_PAD =
  "max-md:px-3 max-md:py-3"

export const MOBILE_WEB_CARD_CLASS =
  "rounded-[14px] border border-white/10 bg-white/5"

/** Edge-to-edge feed cards on phone web; desktop cards stay rounded. */
export const MOBILE_WEB_FEED_CARD_FLUSH =
  "max-md:rounded-none max-md:border-x-0 max-md:shadow-none"
