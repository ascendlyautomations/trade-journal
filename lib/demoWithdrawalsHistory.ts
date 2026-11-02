import { DEMO_ACCOUNTS } from "./demo/fixtures.ts"
import { getDemoPayoutCyclesByAccountId } from "./demo/demoPropfirm.ts"
import {
  buildPayoutHistoryItems,
  type PayoutHistoryAccount,
  type PayoutHistoryItem,
} from "./payoutHistory.ts"

export type DemoWithdrawalsHistory = {
  accounts: PayoutHistoryAccount[]
  items: PayoutHistoryItem[]
}

/** Demo-only payout history from fixtures — no Supabase. */
export function buildDemoWithdrawalsHistory(): DemoWithdrawalsHistory {
  const accounts: PayoutHistoryAccount[] = DEMO_ACCOUNTS.map((account) => ({
    id: account.id,
    name: account.name,
    mode: account.mode,
    category: account.category,
  }))
  const items = buildPayoutHistoryItems({
    accounts,
    entriesByAccount: {},
    cyclesByAccount: getDemoPayoutCyclesByAccountId(
      accounts.map((account) => account.id)
    ),
  })
  return { accounts, items }
}
