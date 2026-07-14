/** Shared layout tokens for public company pages (affiliate, about, contact, legal, guidelines). */

export const COMPANY_PAGE_SHELL =
  "min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 pb-12 text-white sm:px-6 sm:pb-16"

/** Offset below fixed PublicNavbar — single source; pairs with AppShellPadding skip on marketing routes. */
export const COMPANY_PAGE_TOP = "pt-[calc(var(--navbar-height)+7px)]"

/** Space below hero header before main content. */
export const COMPANY_PAGE_HEADER_MARGIN = "mb-5 md:mb-6"

/** Gap between marketing page title and subtitle (mobile tighter). */
export const COMPANY_PAGE_SUBTITLE_GAP = "mt-2 md:mt-3"
