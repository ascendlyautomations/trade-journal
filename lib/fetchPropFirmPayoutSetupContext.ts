import type { SupabaseClient } from "@supabase/supabase-js"
import {
  computePropfirmAccountMetrics,
  parseAccountSizeToNumber,
} from "./propfirmMetrics"
import {
  buildPayoutCycleContext,
  fetchPayoutCycleHistory,
  resolveDefaultPayoutDrawdownBehavior,
  selectActivePayoutCycle,
  type AccountPayoutCycle,
} from "./propfirmPayoutCycles"

const PROPFIRM_ACCOUNT_FIELDS =
  "id,name,account_size,account_number,mode,consistency,max_drawdown,daily_drawdown,profit_target,winning_days,winning_day_threshold,payout_drawdown_behavior,remember_payout_drawdown_behavior"

const PROPFIRM_TRADE_FIELDS =
  "id,pnl,date,trade_date,entry_time,exit_time,created_at"

export type PropFirmPayoutSetupContext = {
  account: Record<string, unknown>
  activePayoutCycle: AccountPayoutCycle | null
  startingBalance: number
  balanceBeforePayout: number
  defaultDrawdownBehavior: ReturnType<
    typeof resolveDefaultPayoutDrawdownBehavior
  >
  defaultRememberDrawdownBehavior: boolean
  cycleTrailingMetrics: ReturnType<
    typeof computePropfirmAccountMetrics
  >["cycleTrailingMetrics"]
}

export async function fetchPropFirmPayoutSetupContext(
  supabase: SupabaseClient,
  userId: string,
  accountId: string
): Promise<{ context: PropFirmPayoutSetupContext | null; error: Error | null }> {
  const { data: account, error: accountError } = await supabase
    .from("accounts")
    .select(PROPFIRM_ACCOUNT_FIELDS)
    .eq("user_id", userId)
    .eq("id", accountId)
    .maybeSingle()

  if (accountError) {
    return { context: null, error: new Error(accountError.message) }
  }
  if (!account) {
    return { context: null, error: new Error("Trading account not found.") }
  }

  const { data: trades, error: tradesError } = await supabase
    .from("trades")
    .select(PROPFIRM_TRADE_FIELDS)
    .eq("account_id", accountId)
    .order("trade_date", { ascending: true })
    .order("entry_time", { ascending: true })

  if (tradesError) {
    return { context: null, error: new Error(tradesError.message) }
  }

  const payoutCycles = await fetchPayoutCycleHistory(supabase, accountId)
  const activePayoutCycle = selectActivePayoutCycle(payoutCycles)
  const startingBalance = parseAccountSizeToNumber(account)
  const payoutCycleContext = buildPayoutCycleContext(
    activePayoutCycle,
    startingBalance
  )
  const metrics = computePropfirmAccountMetrics(
    trades ?? [],
    account,
    payoutCycleContext
  )

  return {
    context: {
      account,
      activePayoutCycle,
      startingBalance: metrics.startingBalance,
      balanceBeforePayout: metrics.lifetimeTrailingMetrics.currentBalance,
      defaultDrawdownBehavior: resolveDefaultPayoutDrawdownBehavior(
        account,
        activePayoutCycle
      ),
      defaultRememberDrawdownBehavior:
        account.remember_payout_drawdown_behavior ?? false,
      cycleTrailingMetrics: metrics.cycleTrailingMetrics,
    },
    error: null,
  }
}
