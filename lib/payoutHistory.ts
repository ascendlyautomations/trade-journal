import type { AccountPayoutEntryRecord } from "@/lib/accountPayoutEntry"
import {
  isPropFirmTradingAccount,
  supportsLiveWithdrawal,
} from "@/lib/accountPayoutPolicy"
import type { AccountPayoutCycle } from "@/lib/propfirmPayoutCycles"
import { selectCompletedPayoutHistory } from "@/lib/propfirmPayoutCycles"

export type PayoutHistorySource = "liveLedger" | "otherLedger" | "fundedCycle"

export type PayoutHistoryItem = {
  id: string
  amount: number
  /** Sort/display instant (UTC noon for ledger `payout_date`). */
  dateMs: number
  /** Ledger `payout_date` (YYYY-MM-DD) when source is manual. */
  payoutDate: string | null
  accountId: string
  ledgerEntryId: string | null
  source: PayoutHistorySource
  note: string | null
  imageUrl: string | null
  cycle: AccountPayoutCycle | null
  isEditable: boolean
}

export type PayoutHistoryAccount = {
  id: string
  name?: string | null
  mode?: unknown
  category?: unknown
}

function ledgerSourceForAccount(
  account: PayoutHistoryAccount | undefined
): PayoutHistorySource {
  if (account && supportsLiveWithdrawal(account)) return "liveLedger"
  return "otherLedger"
}

function payoutDateToMs(payoutDate: string): number {
  const trimmed = String(payoutDate ?? "").trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) return 0
  return Date.parse(`${trimmed}T12:00:00.000Z`)
}

function cycleDateMs(cycle: AccountPayoutCycle): number {
  const raw = cycle.ended_at ?? cycle.started_at
  const ms = Date.parse(String(raw ?? ""))
  return Number.isFinite(ms) ? ms : 0
}

export function buildPayoutHistoryItems(options: {
  accounts: PayoutHistoryAccount[]
  entriesByAccount: Record<string, AccountPayoutEntryRecord[]>
  cyclesByAccount: Record<string, AccountPayoutCycle[]>
}): PayoutHistoryItem[] {
  const accountsById = new Map(
    options.accounts.map((a) => [String(a.id), a] as const)
  )
  const items: PayoutHistoryItem[] = []

  for (const [accountId, entries] of Object.entries(options.entriesByAccount)) {
    const account = accountsById.get(accountId)
    const source = ledgerSourceForAccount(account)
    for (const entry of entries) {
      items.push({
        id: `ledger:${entry.id}`,
        amount: Number(entry.amount) || 0,
        dateMs: payoutDateToMs(entry.payout_date),
        payoutDate: entry.payout_date,
        accountId,
        ledgerEntryId: entry.id,
        source,
        note: entry.note,
        imageUrl: entry.image_url ?? null,
        cycle: null,
        isEditable: true,
      })
    }
  }

  for (const [accountId, cycles] of Object.entries(options.cyclesByAccount)) {
    for (const cycle of selectCompletedPayoutHistory(cycles)) {
      const amount = Number(cycle.payout_amount) || 0
      if (amount <= 0) continue
      items.push({
        id: `cycle:${cycle.id}`,
        amount,
        dateMs: cycleDateMs(cycle),
        payoutDate: null,
        accountId,
        ledgerEntryId: null,
        source: "fundedCycle",
        note: cycle.note,
        imageUrl: null,
        cycle,
        isEditable: false,
      })
    }
  }

  return items.sort((a, b) => b.dateMs - a.dateMs)
}

export function payoutHistorySummary(items: PayoutHistoryItem[]): {
  total: number
  count: number
} {
  if (items.length === 0) return { total: 0, count: 0 }
  const total = items.reduce((sum, item) => sum + item.amount, 0)
  return { total, count: items.length }
}

export function isLiveWithdrawalHistoryItem(
  item: PayoutHistoryItem,
  account: PayoutHistoryAccount | undefined
): boolean {
  switch (item.source) {
    case "fundedCycle":
      return false
    case "liveLedger":
      return true
    case "otherLedger":
      return (
        String(account?.mode ?? "")
          .trim()
          .toLowerCase() === "live"
      )
  }
}

export function isPropPayoutHistoryItem(
  item: PayoutHistoryItem,
  account: PayoutHistoryAccount | undefined
): boolean {
  switch (item.source) {
    case "fundedCycle":
      return true
    case "liveLedger":
      return false
    case "otherLedger":
      return (
        isPropFirmTradingAccount(account) &&
        String(account?.mode ?? "")
          .trim()
          .toLowerCase() === "funded"
      )
  }
}

export function filterLiveWithdrawals(
  items: PayoutHistoryItem[],
  accountsById: Record<string, PayoutHistoryAccount | undefined>
): PayoutHistoryItem[] {
  return items.filter((item) =>
    isLiveWithdrawalHistoryItem(item, accountsById[item.accountId])
  )
}

export function filterPropPayouts(
  items: PayoutHistoryItem[],
  accountsById: Record<string, PayoutHistoryAccount | undefined>
): PayoutHistoryItem[] {
  return items.filter((item) =>
    isPropPayoutHistoryItem(item, accountsById[item.accountId])
  )
}

export function payoutHistoryItemHref(itemId: string): string {
  return `/withdrawals/${encodeURIComponent(itemId)}`
}
