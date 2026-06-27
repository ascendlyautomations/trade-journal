import { formatAccountNameWithSizeDisplay } from "./tradeAccountDisplay.ts"

export type TradingAccountSearchRow = {
  name: string
  size: string
  account_number: string | null
}

/** Client-side Settings search — display name (incl. size) and brokerage Account ID. */
export function matchesTradingAccountSearch(
  account: TradingAccountSearchRow,
  rawQuery: string
): boolean {
  const q = rawQuery.trim().toLowerCase()
  if (!q) return true

  const displayName = formatAccountNameWithSizeDisplay(
    account.name,
    account.size
  ).toLowerCase()
  if (displayName.includes(q)) return true

  const accountId = account.account_number?.trim().toLowerCase()
  return Boolean(accountId && accountId.includes(q))
}
