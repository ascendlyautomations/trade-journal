/** Normalize account_type for feed badges. */
export function normalizeFeedAccountType(raw: unknown): string {
  return String(raw ?? "").trim().toLowerCase()
}

/**
 * Resolve trades.account_type the same way Input Trade save + feed badges do.
 * Live accounts often have a null mode in accounts; save defaults those to "live".
 */
export function resolveFeedTradeAccountType(params: {
  mode?: string | null
  accountType?: string | null
  lockedAccountType?: string | null
  isPro?: boolean
}): string {
  const modeLower = normalizeFeedAccountType(
    params.mode ?? params.accountType ?? "live"
  )

  if (
    !params.isPro &&
    modeLower !== "backtest" &&
    modeLower !== "imported"
  ) {
    const lockedType = normalizeFeedAccountType(params.lockedAccountType)
    if (lockedType) return lockedType || modeLower
  }

  return modeLower || "live"
}
