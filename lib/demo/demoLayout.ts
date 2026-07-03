export const DEMO_BANNER_LAYOUT_CLASS = "tradetraxs-demo-banner-active"

/** Sync document-level CSS vars so navbar + page content sit below the demo banner. */
export function syncDemoBannerLayout(active: boolean): void {
  if (typeof document === "undefined") return
  document.documentElement.classList.toggle(DEMO_BANNER_LAYOUT_CLASS, active)
}
