import type { AccountPayoutEntryRecord } from "@/lib/accountPayoutEntry"
import {
  isPropFirmTradingAccount,
  supportsLiveWithdrawal,
} from "@/lib/accountPayoutPolicy"
import type { AccountPayoutCycle } from "@/lib/propfirmPayoutCycles"
import { selectCompletedPayoutHistory } from "@/lib/propfirmPayoutCycles"

export type PayoutHistorySource =
  | "liveLedger"
  | "otherLedger"
  | "fundedCycle"
  | "achievementProp"
  | "achievementLive"

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
    case "achievementProp":
      return false
    case "achievementLive":
      return true
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
      // Past prop payouts, including eval accounts, were saved on the ledger.
      return isPropFirmTradingAccount(account)
    case "achievementProp":
      return true
    case "achievementLive":
      return false
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

/** Prop payouts, plus an achievement withdrawal once a firm is chosen for it. */
export function filterPropFirmTrackerPayouts(
  items: PayoutHistoryItem[],
  accountsById: Record<string, PayoutHistoryAccount | undefined>,
  assignments: Record<string, string>
): PayoutHistoryItem[] {
  const prop = filterPropPayouts(items, accountsById)
  const ids = new Set(prop.map((item) => item.id))
  const linked = items.filter(
    (item) =>
      item.source === "achievementLive" &&
      Boolean(assignments[item.id]?.trim()) &&
      !ids.has(item.id)
  )
  return [...prop, ...linked]
}

export function payoutHistoryItemHref(itemId: string): string {
  return `/withdrawals/${encodeURIComponent(itemId)}`
}

const MATCH_WINDOW_MS = 14 * 24 * 60 * 60 * 1000

export type UnmatchedPayoutAchievement = {
  id: string
  achievementType: string | null
  title: string | null
  amount: number
  achievedAt: string | null
  createdAt: string | null
  accountId: string | null
  linkedCycleId: string | null
  linkedEntryId: string | null
}

/** Payout achievements that never became a withdrawal or payout cycle. */
export function payoutAchievementsMissingFromHistory(
  achievements: UnmatchedPayoutAchievement[],
  items: PayoutHistoryItem[]
): PayoutHistoryItem[] {
  const completedCycleIds = new Set(
    items
      .filter((item) => item.source === "fundedCycle")
      .map((item) => item.id.replace(/^cycle:/, ""))
  )
  const ledgerIds = new Set(
    items.map((item) => item.ledgerEntryId).filter((id): id is string => Boolean(id))
  )

  return achievements.flatMap((achievement) => {
    const amount = Number(achievement.amount)
    if (!Number.isFinite(amount) || amount <= 0) return []
    if (achievement.linkedEntryId && ledgerIds.has(achievement.linkedEntryId)) return []
    if (achievement.linkedCycleId && completedCycleIds.has(achievement.linkedCycleId)) return []
    const dateMs = achievementInstant(achievement.achievedAt, achievement.createdAt)
    const accountId = String(achievement.accountId ?? "").trim()
    if (
      accountId &&
      items.some(
        (item) =>
          item.accountId === accountId &&
          Math.abs(item.amount - amount) < 0.01 &&
          Math.abs(item.dateMs - dateMs) <= MATCH_WINDOW_MS
      )
    ) {
      return []
    }
    const prop = isPropFirmPayoutAchievement(achievement.achievementType)
    const payoutDate = dateMs > 0 ? new Date(dateMs).toISOString().slice(0, 10) : null
    return [{
      id: `achievement:${achievement.id}`,
      amount,
      dateMs,
      payoutDate,
      accountId,
      ledgerEntryId: null,
      source: prop ? "achievementProp" : "achievementLive",
      note: achievement.title?.trim() || (prop ? "Prop Firm Payout" : "Payout"),
      imageUrl: null,
      cycle: null,
      isEditable: false,
    } satisfies PayoutHistoryItem]
  })
}

function achievementInstant(achievedAt: string | null, createdAt: string | null): number {
  const ms = Date.parse(String(achievedAt || createdAt || ""))
  return Number.isFinite(ms) ? ms : 0
}

function isPropFirmPayoutAchievement(type: string | null): boolean {
  const value = String(type ?? "").trim().toLowerCase()
  return value === "prop_firm_payout" || value === "prop_firm_payouts"
}
