/**
 * Shared page title styling — solid dark blue only (no gradient text on page headers).
 * Matches Input Trade / Backtest Lab (`text-blue-300`).
 */

/** Solid page title color — single source of truth. */
export const PAGE_HEADING_COLOR_CLASS = "text-blue-300"

/** Centered submission-style page title (Support, Feedback, Help, CSV Support). */
export const PAGE_HEADING_CENTERED_CLASS = `text-center text-2xl font-semibold ${PAGE_HEADING_COLOR_CLASS} md:text-3xl`

/** Standard in-app page title (Input Trade, Backtest Lab). */
export const PAGE_HEADING_APP_CLASS = `text-xl font-semibold ${PAGE_HEADING_COLOR_CLASS} md:text-2xl`

/** Shared company / legal page title — same medium desktop size as marketing heroes. */
export const PAGE_HEADING_LARGE_CLASS = `text-xl font-bold ${PAGE_HEADING_COLOR_CLASS} md:text-3xl`

/** Public marketing page title (FAQ / pricing / company heroes) — medium desktop size. */
export const PAGE_HEADING_MARKETING_CLASS = `text-xl font-bold ${PAGE_HEADING_COLOR_CLASS} md:text-3xl`

/** Admin console page title. */
export const PAGE_HEADING_ADMIN_CLASS = `text-2xl font-bold ${PAGE_HEADING_COLOR_CLASS} md:text-3xl`
