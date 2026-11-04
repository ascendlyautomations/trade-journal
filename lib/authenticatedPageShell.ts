/**
 * Shared horizontal bounds for authenticated web pages (desktop/tablet md+).
 * Mobile padding stays page-specific via className overrides on the container.
 *
 * Do not use on marketing, legal, or login surfaces.
 */

/** Primary content column — 1600px max, centered. */
export const AUTH_PAGE_CONTAINER_CLASS =
  "mx-auto w-full min-w-0 max-w-[1600px] md:px-6 xl:px-8 2xl:px-12"

/** Same max width without horizontal padding (when an outer shell already pads). */
export const AUTH_PAGE_CONTAINER_NO_PAD_CLASS =
  "mx-auto w-full min-w-0 max-w-[1600px]"

/** Alias for feed column wrapper (same bounds as primary container). */
export const AUTH_FEED_WORKSPACE_CLASS = AUTH_PAGE_CONTAINER_CLASS
