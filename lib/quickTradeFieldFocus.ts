import type { QuickTradeFormField } from "./validateQuickTradeForm"

export const QUICK_TRADE_FIELD_ELEMENT_IDS: Partial<
  Record<QuickTradeFormField, string>
> = {
  account: "quick-trade-account-trigger",
  symbol: "quick-trade-symbol",
  pnl: "quick-trade-pnl",
  points: "quick-trade-points",
  contracts: "quick-trade-contracts",
  rr: "quick-trade-rr",
  entryDate: "quick-entry-date",
  exitDate: "quick-exit-date",
  entryTime: "quick-entry-time",
  exitTime: "quick-exit-time",
  entryPrice: "quick-entry-price",
  exitPrice: "quick-exit-price",
}

type FocusQuickTradeFieldOptions = {
  openAdvanced?: () => void
}

export function focusQuickTradeField(
  field: QuickTradeFormField,
  options?: FocusQuickTradeFieldOptions
) {
  if (field === "entryPrice" || field === "exitPrice") {
    options?.openAdvanced?.()
  }

  window.requestAnimationFrame(() => {
    const elementId = QUICK_TRADE_FIELD_ELEMENT_IDS[field]
    if (!elementId) return

    const element = document.getElementById(elementId)
    if (!element) return

    element.scrollIntoView({ block: "center", behavior: "smooth" })
    element.focus({ preventScroll: true })
  })
}
