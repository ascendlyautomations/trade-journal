import type { CopyTradingGroup } from "./copyTradingGroups.ts"
import { resolveCopyGroupAccountIdsForFilter } from "./tradeAccountSelection.ts"
import type { AccountRowForDisplay } from "./tradeAccountDisplay.ts"
import { tradeMatchesAccountFilter } from "./tradeAccountDisplay.ts"
import { tradeMatchesDashboardTimeFilter } from "./dashboardTradeDate.ts"

/** Default dashboard timeframe on first load (matches native Home). */
export const DASHBOARD_DEFAULT_TIME_FILTER = "30d"

/** Automatic expansion order when the default window has no trades. */
export const DASHBOARD_INITIAL_TIMEFRAME_FALLBACK_ORDER = [
  "30d",
  "90d",
  "1y",
  "all",
] as const

export type DashboardInitialTimeframe =
  (typeof DASHBOARD_INITIAL_TIMEFRAME_FALLBACK_ORDER)[number]

type TradeForScope = {
  account_name?: string | null
  account_size?: string | null
  account_id?: string | null
  mode?: string | null
  account_type?: string | null
  entry_time?: string | null
  exit_time?: string | null
  created_at?: string | null
  date?: string | null
  trade_date?: string | null
}

function tradeMatchesDashboardScopeFilters(
  trade: TradeForScope,
  accountFilter: string,
  accountTypeFilter: string,
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null,
  copyGroups?: readonly CopyTradingGroup[]
): boolean {
  const id = String(trade.account_id ?? "").trim()
  const accountRow = id && accountById ? accountById[id] : null
  const copyGroupAccountIds = resolveCopyGroupAccountIdsForFilter(
    accountFilter,
    copyGroups ?? []
  )
  if (
    !tradeMatchesAccountFilter(trade, accountFilter, accountRow, {
      copyGroupAccountIds: copyGroupAccountIds ?? undefined,
    })
  ) {
    return false
  }
  if (accountTypeFilter !== "all") {
    const tradeAcct = String(trade.mode ?? trade.account_type ?? "")
      .toLowerCase()
      .trim()
    const selectedAcct = accountTypeFilter.toLowerCase().trim()
    if (tradeAcct !== selectedAcct) return false
  }
  return true
}

export function countDashboardTradesInTimeframe(args: {
  trades: TradeForScope[]
  timeFilter: string
  accountFilter: string
  accountTypeFilter: string
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
  copyGroups?: readonly CopyTradingGroup[]
  now?: Date
}): number {
  const now = args.now ?? new Date()
  let count = 0
  for (const trade of args.trades) {
    if (
      !tradeMatchesDashboardScopeFilters(
        trade,
        args.accountFilter,
        args.accountTypeFilter,
        args.accountById,
        args.copyGroups
      )
    ) {
      continue
    }
    if (
      !tradeMatchesDashboardTimeFilter(trade, args.timeFilter, now, "", "")
    ) {
      continue
    }
    count += 1
  }
  return count
}

/** First preset in ``DASHBOARD_INITIAL_TIMEFRAME_FALLBACK_ORDER`` with ≥1 scoped trade. */
export function resolveInitialDashboardTimeframe(args: {
  trades: TradeForScope[]
  accountFilter: string
  accountTypeFilter: string
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
  copyGroups?: readonly CopyTradingGroup[]
  now?: Date
}): DashboardInitialTimeframe {
  for (const timeFilter of DASHBOARD_INITIAL_TIMEFRAME_FALLBACK_ORDER) {
    if (
      countDashboardTradesInTimeframe({
        ...args,
        timeFilter,
      }) > 0
    ) {
      return timeFilter
    }
  }
  return DASHBOARD_DEFAULT_TIME_FILTER
}

/** Legacy persisted values → rolling presets (dashboard only). */
export function migrateLegacyDashboardTimeFilter(
  value: string | undefined
): string {
  switch (value) {
    case "weekly":
      return "7d"
    case "monthly":
      return "30d"
    case "yearly":
      return "1y"
    case "daily":
      return "daily"
    default:
      return value ?? DASHBOARD_DEFAULT_TIME_FILTER
  }
}

export function isDashboardAutomaticTimeframeCandidate(
  value: string
): value is DashboardInitialTimeframe {
  return (
    DASHBOARD_INITIAL_TIMEFRAME_FALLBACK_ORDER as readonly string[]
  ).includes(value)
}
