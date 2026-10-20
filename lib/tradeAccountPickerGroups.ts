import type { TradeAccountOption } from "@/app/components/TradeAccountPicker"

export type TradeAccountPickerScope = "default" | "backtest_only"

export type TradeAccountPickerMenuEntry =
  | { type: "section"; id: string; label: string }
  | { type: "account"; account: TradeAccountOption }

/** Authoritative Backtest account (category or mode). */
export function isAuthoritativeBacktestAccount(account: {
  mode?: unknown
  category?: unknown
}): boolean {
  const category = String(account.category ?? "").trim().toLowerCase()
  const mode = String(account.mode ?? "").trim().toLowerCase()
  return category === "backtest" || mode === "backtest"
}

const NON_BACKTEST_SECTIONS: Array<{ id: string; label: string }> = [
  { id: "live", label: "Live Accounts" },
  { id: "eval", label: "Evaluation Accounts" },
  { id: "funded", label: "Funded Accounts" },
  { id: "sim", label: "Sim Accounts" },
  { id: "other", label: "Other Accounts" },
]

function sectionIdForAccount(account: TradeAccountOption): string {
  if (isAuthoritativeBacktestAccount(account)) return "backtest"
  const mode = String(account.mode ?? "")
    .trim()
    .toLowerCase()
  if (mode === "eval" || mode === "evaluation") return "eval"
  if (mode === "funded") return "funded"
  if (mode === "live") return "live"
  if (mode === "sim") return "sim"
  return "other"
}

function sortAccountsByName(
  accounts: readonly TradeAccountOption[]
): TradeAccountOption[] {
  return [...accounts].sort((a, b) =>
    String(a.name ?? "").localeCompare(String(b.name ?? ""), undefined, {
      sensitivity: "base",
    })
  )
}

export function filterAccountsForPickerScope<
  T extends { mode?: unknown; category?: unknown },
>(accounts: readonly T[], scope: TradeAccountPickerScope): T[] {
  if (scope === "backtest_only") {
    return accounts.filter((row) => isAuthoritativeBacktestAccount(row))
  }
  return [...accounts]
}

export function buildTradeAccountPickerMenuEntries(
  accounts: readonly TradeAccountOption[],
  scope: TradeAccountPickerScope = "default"
): TradeAccountPickerMenuEntry[] {
  const scoped = filterAccountsForPickerScope(accounts, scope)
  const backtest = sortAccountsByName(
    scoped.filter((row) => isAuthoritativeBacktestAccount(row))
  )
  const nonBacktest = sortAccountsByName(
    scoped.filter((row) => !isAuthoritativeBacktestAccount(row))
  )

  const entries: TradeAccountPickerMenuEntry[] = []

  if (scope === "backtest_only") {
    if (backtest.length) {
      entries.push({ type: "section", id: "backtest", label: "Backtest Accounts" })
      for (const account of backtest) {
        entries.push({ type: "account", account })
      }
    }
    return entries
  }

  if (backtest.length) {
    entries.push({ type: "section", id: "backtest", label: "Backtest Accounts" })
    for (const account of backtest) {
      entries.push({ type: "account", account })
    }
  }

  const buckets = new Map<string, TradeAccountOption[]>()
  for (const account of nonBacktest) {
    const id = sectionIdForAccount(account)
    if (!buckets.has(id)) buckets.set(id, [])
    buckets.get(id)!.push(account)
  }

  for (const section of NON_BACKTEST_SECTIONS) {
    const bucket = buckets.get(section.id)
    if (!bucket?.length) continue
    entries.push({ type: "section", id: section.id, label: section.label })
    for (const account of bucket) {
      entries.push({ type: "account", account })
    }
  }

  return entries
}

/** Collapse by account row count; section headers count only when followed by a visible account. */
export function sliceTradeAccountPickerMenuEntries(
  entries: readonly TradeAccountPickerMenuEntry[],
  limit: number,
  expanded: boolean
): TradeAccountPickerMenuEntry[] {
  if (expanded) return [...entries]

  const accountCount = entries.filter((e) => e.type === "account").length
  if (accountCount <= limit) return [...entries]

  const result: TradeAccountPickerMenuEntry[] = []
  let visibleAccounts = 0
  let pendingSection: TradeAccountPickerMenuEntry | null = null

  for (const entry of entries) {
    if (entry.type === "section") {
      pendingSection = entry
      continue
    }
    if (visibleAccounts >= limit) break
    if (pendingSection) {
      result.push(pendingSection)
      pendingSection = null
    }
    result.push(entry)
    visibleAccounts += 1
  }

  return result
}

export function tradeAccountPickerMenuAccountCount(
  entries: readonly TradeAccountPickerMenuEntry[]
): number {
  return entries.filter((entry) => entry.type === "account").length
}
