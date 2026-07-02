import type { AccountPayoutCycle } from "@/lib/propfirmPayoutCycles"
import type { PropfirmTrade } from "@/lib/propfirmMetrics"
import { DEMO_ACCOUNTS, DEMO_PAYOUT_CYCLES, DEMO_TRADES } from "./fixtures"

export function getDemoPropfirmAccounts() {
  return DEMO_ACCOUNTS.filter((account) => account.category === "Prop Firm")
}

export function getDemoPropfirmTrades(accountIds: string[]): PropfirmTrade[] {
  const idSet = new Set(accountIds.map(String))
  return DEMO_TRADES.filter((trade) => idSet.has(String(trade.account_id))).map(
    (trade) => ({
      id: trade.id,
      pnl: trade.pnl,
      date: trade.date ?? trade.trade_date ?? null,
      trade_date: trade.trade_date ?? trade.date ?? null,
      entry_time: trade.entry_time,
      exit_time: trade.exit_time,
      created_at: trade.created_at,
    })
  )
}

export function getDemoPayoutCyclesByAccountId(
  accountIds: string[]
): Record<string, AccountPayoutCycle[]> {
  const result: Record<string, AccountPayoutCycle[]> = {}
  for (const accountId of accountIds) {
    const cycles = DEMO_PAYOUT_CYCLES[accountId]
    if (cycles?.length) {
      result[accountId] = cycles as AccountPayoutCycle[]
    }
  }
  return result
}
