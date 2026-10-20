import type { PayoutHistoryAccount, PayoutHistoryItem } from "@/lib/payoutHistory"
import {
  buildAccountFilterOptionsFromRows,
  type AccountRowForDisplay,
} from "@/lib/tradeAccountDisplay"
export function accountIdFromWithdrawalsAccountFilter(
  accountFilter: string
): string | null {
  if (!accountFilter || accountFilter === "all") return null
  const segments = accountFilter.split("|")
  const id = segments[segments.length - 1]?.trim()
  return id || null
}

export function payoutHistoryItemDateKey(item: PayoutHistoryItem): string {
  if (item.payoutDate && /^\d{4}-\d{2}-\d{2}$/.test(item.payoutDate)) {
    return item.payoutDate
  }
  const ms = item.dateMs
  if (!Number.isFinite(ms) || ms <= 0) return ""
  const d = new Date(ms)
  const y = d.getUTCFullYear()
  const m = String(d.getUTCMonth() + 1).padStart(2, "0")
  const day = String(d.getUTCDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

export function payoutHistoryItemChartDate(item: PayoutHistoryItem): string {
  const key = payoutHistoryItemDateKey(item)
  return key ? `${key}T12:00:00.000Z` : new Date(item.dateMs).toISOString()
}

export function filterPayoutHistoryByAccountFilter(
  items: readonly PayoutHistoryItem[],
  accountFilter: string
): PayoutHistoryItem[] {
  const accountId = accountIdFromWithdrawalsAccountFilter(accountFilter)
  if (!accountId) return [...items]
  return items.filter((item) => item.accountId === accountId)
}

export type WithdrawalCumulativeChartPoint = {
  date: string
  dateKey: string
  cumulative: number
  /** Withdrawal amount at this step (0 for the baseline point). */
  stepAmount: number
}

export function buildCumulativeWithdrawalChartPoints(
  items: readonly PayoutHistoryItem[]
): WithdrawalCumulativeChartPoint[] {
  const sorted = [...items].sort((a, b) => {
    const diff = a.dateMs - b.dateMs
    if (diff !== 0) return diff
    return a.id.localeCompare(b.id)
  })
  if (sorted.length === 0) return []

  const points: WithdrawalCumulativeChartPoint[] = []
  const firstKey = payoutHistoryItemDateKey(sorted[0])
  if (firstKey) {
    points.push({
      date: `${firstKey}T12:00:00.000Z`,
      dateKey: firstKey,
      cumulative: 0,
      stepAmount: 0,
    })
  }

  let cumulative = 0
  for (const item of sorted) {
    cumulative += item.amount
    const dateKey = payoutHistoryItemDateKey(item)
    points.push({
      date: payoutHistoryItemChartDate(item),
      dateKey,
      cumulative,
      stepAmount: item.amount,
    })
  }
  return points
}

export type WithdrawalsByDateEntry = {
  dateKey: string
  total: number
  count: number
}

export function groupWithdrawalsByDateKey(
  items: readonly PayoutHistoryItem[]
): Map<string, WithdrawalsByDateEntry> {
  const map = new Map<string, WithdrawalsByDateEntry>()
  for (const item of items) {
    const dateKey = payoutHistoryItemDateKey(item)
    if (!dateKey) continue
    const prev = map.get(dateKey) ?? { dateKey, total: 0, count: 0 }
    prev.total += item.amount
    prev.count += 1
    map.set(dateKey, prev)
  }
  return map
}

export function buildWithdrawalsAccountFilterOptions(
  accounts: readonly PayoutHistoryAccount[]
) {
  const rows: AccountRowForDisplay[] = accounts.map((account) => ({
    id: account.id,
    name: account.name ?? "Account",
    mode:
      account.mode != null && account.mode !== ""
        ? String(account.mode)
        : null,
    account_size: null,
    account_number: null,
  }))
  return buildAccountFilterOptionsFromRows(rows)
}

export function filterPayoutHistoryBySelectedDate(
  items: readonly PayoutHistoryItem[],
  selectedDateKey: string | null
): PayoutHistoryItem[] {
  if (!selectedDateKey) return [...items]
  return items.filter(
    (item) => payoutHistoryItemDateKey(item) === selectedDateKey
  )
}
