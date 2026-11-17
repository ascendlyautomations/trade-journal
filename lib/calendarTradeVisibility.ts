import { tradeMatchesAccountFilter } from "./tradeAccountDisplay.ts"
import type { AccountRowForDisplay } from "./tradeAccountDisplay.ts"

type CalendarTrade = {
  account_id?: string | null
  mode?: string | null
  account_type?: string | null
}

/** Same account and mode checks the calendar grid uses for filteredTrades. */
export function tradeVisibleInCalendarFilters(
  trade: CalendarTrade,
  input: {
    accountFilter: string
    accountRow?: AccountRowForDisplay | null
    selectedMode: string
  }
): boolean {
  if (input.accountFilter !== "all") {
    if (!tradeMatchesAccountFilter(trade, input.accountFilter, input.accountRow)) {
      return false
    }
  }
  if (input.selectedMode === "all") return true
  const mode = input.selectedMode.toLowerCase()
  return (
    trade.mode?.toLowerCase() === mode ||
    trade.account_type?.toLowerCase() === mode
  )
}
