export const MOBILE_WEB_OPEN_QUICK_TRADE_EVENT = "tj-mobile-web-open-quick-trade"

export function openMobileWebQuickTrade() {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent(MOBILE_WEB_OPEN_QUICK_TRADE_EVENT))
}
