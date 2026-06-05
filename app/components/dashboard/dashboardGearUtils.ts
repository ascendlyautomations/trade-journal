import type { DashboardGearPersistedPrefs } from "./dashboardGearTypes"

/** Strip to digits + one dot; max 2 decimal places (internal value for save). */
export function sanitizeDrawdownLimitInput(raw: string): string {
  let t = raw.replace(/[^0-9.]/g, "")
  const dot = t.indexOf(".")
  if (dot !== -1) {
    t = t.slice(0, dot + 1) + t.slice(dot + 1).replace(/\./g, "")
  }
  const [intPart = "", frac] = t.split(".")
  if (frac !== undefined) {
    return `${intPart}.${frac.slice(0, 2)}`
  }
  return intPart
}

export function finalizeDrawdownLimitInput(raw: string): string {
  let t = sanitizeDrawdownLimitInput(raw)
  if (t.endsWith(".")) t = t.slice(0, -1)
  return t
}

export function formatDrawdownLimitForDisplay(
  raw: string,
  focused: boolean
): string {
  const s = sanitizeDrawdownLimitInput(raw)
  if (focused) return s
  if (s === "" || s === ".") return ""
  const n = Number(s)
  if (!Number.isFinite(n) || n < 0) return ""
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  }).format(n)
}

export const DASHBOARD_GEAR_SECTION_TITLE =
  "text-xs md:text-sm text-gray-400 uppercase tracking-wide mb-2"

export const DASHBOARD_VALID_TIME_FILTERS = [
  "all",
  "daily",
  "weekly",
  "monthly",
  "yearly",
  "custom",
] as const

export const DASHBOARD_VALID_ACCOUNT_TYPE_FILTERS = [
  "all",
  "funded",
  "eval",
  "live",
] as const

export type DashboardAccountOption = { value: string; label?: string }

type TradeForAccountFilter = {
  account_name?: unknown
  account_size?: unknown
  account_id?: unknown
  mode?: unknown
  account_type?: unknown
}

export function sanitizeDashboardTimeFilter(value: string | undefined): string {
  if (
    value &&
    (DASHBOARD_VALID_TIME_FILTERS as readonly string[]).includes(value)
  ) {
    return value
  }
  return "all"
}

export function sanitizeDashboardAccountTypeFilter(
  value: string | undefined
): string {
  if (
    value &&
    (DASHBOARD_VALID_ACCOUNT_TYPE_FILTERS as readonly string[]).includes(value)
  ) {
    return value
  }
  return "all"
}

/** Same rule as dashboard gear Save: unknown account keys fall back to "all". */
export function sanitizeDashboardAccountFilter(
  accountFilter: string | undefined,
  accountOptions: DashboardAccountOption[]
): string {
  if (!accountFilter || accountFilter === "all") return "all"
  return accountOptions.some((a) => a.value === accountFilter)
    ? accountFilter
    : "all"
}

export function buildDashboardAccountOptionsFromTrades(
  trades: TradeForAccountFilter[]
): DashboardAccountOption[] {
  const accountMap = new Map<string, DashboardAccountOption>()
  trades
    .filter((t) => t.account_name && t.account_size && t.account_id)
    .forEach((t) => {
      const accountName = String(t.account_name ?? "").trim()
      const size = String(t.account_size ?? "").trim()
      const id = String(t.account_id ?? "").trim()
      const value = `${accountName}|${size}|${id}`
      if (!accountMap.has(value)) {
        accountMap.set(value, {
          value,
          label: `${accountName} ${size}`.trim(),
        })
      }
    })
  return Array.from(accountMap.values())
}

export function tradeMatchesDashboardAccountFilters(
  trade: TradeForAccountFilter,
  accountFilter: string,
  accountTypeFilter: string
): boolean {
  if (accountFilter !== "all") {
    const accountName = String(trade.account_name ?? "").trim()
    const size = String(trade.account_size ?? "").trim()
    const id = String(trade.account_id ?? "").trim()
    const accountKey = `${accountName}|${size}|${id}`
    if (accountKey !== accountFilter) return false
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

export function sanitizeHydratedDashboardFilters(args: {
  prefs: Partial<DashboardGearPersistedPrefs>
  trades: TradeForAccountFilter[]
}): Pick<
  DashboardGearPersistedPrefs,
  "timeFilter" | "accountFilter" | "accountTypeFilter"
> {
  const accountOptions = buildDashboardAccountOptionsFromTrades(args.trades)

  let timeFilter = sanitizeDashboardTimeFilter(args.prefs.timeFilter)
  let accountFilter = sanitizeDashboardAccountFilter(
    args.prefs.accountFilter,
    accountOptions
  )
  let accountTypeFilter = sanitizeDashboardAccountTypeFilter(
    args.prefs.accountTypeFilter
  )

  if (args.trades.length > 0) {
    const hasAnyTrade = args.trades.some((t) =>
      tradeMatchesDashboardAccountFilters(t, "all", "all")
    )
    const matchesHydrated = args.trades.some((t) =>
      tradeMatchesDashboardAccountFilters(t, accountFilter, accountTypeFilter)
    )
    if (hasAnyTrade && !matchesHydrated) {
      accountFilter = "all"
      accountTypeFilter = "all"
    }
  }

  return { timeFilter, accountFilter, accountTypeFilter }
}
