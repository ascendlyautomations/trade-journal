/** Minimal helpers for Free-plan rules — no Supabase / tradingAccounts imports. */

export type CopyTradingGroupAccountIds = {
  accountIds: readonly string[]
}

export const COPY_TRADING_ACCOUNT_FREE_VIEW_ONLY_NOTE =
  "Linked to Copy Trading — view-only on Free (history and filters only)."

export function copyTradingLinkedAccountIdSet(
  groups: readonly CopyTradingGroupAccountIds[]
): Set<string> {
  const ids = new Set<string>()
  for (const group of groups) {
    for (const accountId of group.accountIds) {
      const trimmed = String(accountId ?? "").trim()
      if (trimmed) ids.add(trimmed)
    }
  }
  return ids
}
