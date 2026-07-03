/**
 * Public marketing page cache tiers.
 *
 * Static copy (hero, FAQ, legal, pricing text): daily ISR at the CDN.
 * Homepage semi-static blocks (reviews, featured trades): 30-minute data cache
 * via unstable_cache inside Suspense boundaries so the shell stays static.
 */

/** Fully static marketing copy — hero, FAQ, legal, pricing, about, etc. */
export const MARKETING_STATIC_REVALIDATE_SECONDS = 86_400 as const

/** Homepage static shell — hero, features, pricing preview, FAQ sections. */
export const LANDING_PAGE_STATIC_REVALIDATE_SECONDS = 86_400 as const

/** Featured reviews — refresh every 30 minutes. */
export const LANDING_REVIEWS_REVALIDATE_SECONDS = 1_800

/** Featured trades — refresh every 30 minutes. */
export const LANDING_FEATURED_TRADES_REVALIDATE_SECONDS = 1_800
