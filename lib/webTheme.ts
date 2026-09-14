/** Web appearance themes (Phase 1 — tradetraxs only active for users). */

export const WEB_THEMES = ["tradetraxs", "light", "dark"] as const

export type WebTheme = (typeof WEB_THEMES)[number]

/** Explicit default for SSR and until persistence exists. */
export const DEFAULT_WEB_THEME: WebTheme = "tradetraxs"

export function isWebTheme(value: string): value is WebTheme {
  return (WEB_THEMES as readonly string[]).includes(value)
}
