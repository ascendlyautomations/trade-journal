import type { AccountRowForDisplay } from "@/lib/tradeAccountDisplay"
import {
  buildAccountFilterOptionsFromRows,
  tradeMatchesAccountFilter,
} from "@/lib/tradeAccountDisplay"
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

export function buildDashboardAccountOptionsFromAccounts(
  accountRows: readonly AccountRowForDisplay[]
): DashboardAccountOption[] {
  return buildAccountFilterOptionsFromRows(accountRows, {
    includeAccountNumberInLabel: false,
  })
}

/** @deprecated Prefer `buildDashboardAccountOptionsFromAccounts`. */
export function buildDashboardAccountOptionsFromTrades(
  _trades: TradeForAccountFilter[],
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
): DashboardAccountOption[] {
  const rows = accountById ? Object.values(accountById).filter(Boolean) : []
  return buildDashboardAccountOptionsFromAccounts(
    rows as AccountRowForDisplay[]
  )
}

export function tradeMatchesDashboardAccountFilters(
  trade: TradeForAccountFilter,
  accountFilter: string,
  accountTypeFilter: string,
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
): boolean {
  const id = String(trade.account_id ?? "").trim()
  const accountRow = id && accountById ? accountById[id] : null
  if (!tradeMatchesAccountFilter(trade, accountFilter, accountRow)) {
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

/** Last segment of `name|size|accountId` dashboard account filter keys. */
export function accountIdFromDashboardAccountFilterKey(
  accountFilter: string | undefined
): string | null {
  if (!accountFilter || accountFilter === "all") return null
  const segments = accountFilter.split("|")
  const id = segments[segments.length - 1]?.trim()
  return id || null
}

/** Prop Firm dashboard link — prop firm account selected OR Eval/Funded mode. */
export function shouldShowPropFirmDashboardLink(args: {
  accountFilter: string
  accountTypeFilter: string
  accountById: Record<string, { category?: string | null } | null | undefined>
}): boolean {
  const { accountFilter, accountTypeFilter, accountById } = args

  if (accountTypeFilter === "eval" || accountTypeFilter === "funded") {
    return true
  }

  if (!accountFilter || accountFilter === "all") return false

  const accountId = accountIdFromDashboardAccountFilterKey(accountFilter)
  if (!accountId) return false

  return accountById[accountId]?.category === "Prop Firm"
}

export function sanitizeHydratedDashboardFilters(args: {
  prefs: Partial<DashboardGearPersistedPrefs>
  trades: TradeForAccountFilter[]
  accountRows: readonly AccountRowForDisplay[]
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
}): Pick<
  DashboardGearPersistedPrefs,
  "timeFilter" | "accountFilter" | "accountTypeFilter"
> {
  const accountOptions = buildDashboardAccountOptionsFromAccounts(args.accountRows)

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
      tradeMatchesDashboardAccountFilters(
        t,
        accountFilter,
        accountTypeFilter,
        args.accountById
      )
    )
    if (hasAnyTrade && !matchesHydrated) {
      accountFilter = "all"
      accountTypeFilter = "all"
    }
  }

  return { timeFilter, accountFilter, accountTypeFilter }
}
