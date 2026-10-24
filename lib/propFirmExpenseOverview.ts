import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  PROP_FIRM_EXPENSE_TYPES,
  propFirmExpenseTypeLabel,
  type PropFirmExpenseRecord,
  type PropFirmExpenseType,
} from "./propFirmExpenses.ts"
import {
  estimatedTaxReserveCents,
  firmNameForPropPayout,
  propFirmKey,
  UNASSIGNED_PROP_FIRM,
} from "./propFirmExpenseTaxExport.ts"
import { isPropFirmTrackerExpense } from "./propFirmExpenses.ts"

export const DEFAULT_TAX_RESERVE_PERCENT = 25
export const TAX_RESERVE_PRESETS = [15, 20, 25, 30] as const
export const UNASSIGNED_FIRM_KEY = "__unassigned__"

const MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

export type PropFirmOverviewPayout = {
  payoutDate: string
  accountId: string | null
  amountCents: number
  assignedFirmName?: string | null
  accountName?: string | null
}

export type PropFirmProfitability = {
  key: string
  label: string
  spentCents: number
  payoutCents: number
  netCents: number
  shortfallCents: number
}

export type PropFirmMonthComparison = {
  monthKey: string
  label: string
  expenseCents: number
  payoutCents: number
}

export type PropFirmYearOverview = {
  year: number
  payoutCents: number
  expenseCents: number
  netCents: number
  deductibleEstimateCents: number
  reserveCents: number
  firms: PropFirmProfitability[]
  mostProfitableFirmKey: string | null
  byCategory: Array<{ key: string; label: string; totalCents: number }>
  spendingByFirm: Array<{ key: string; label: string; totalCents: number }>
  months: PropFirmMonthComparison[]
}

export function parseTaxReservePercent(input: string): number | null {
  const raw = input.trim().replace(/%$/, "")
  if (!/^\d{1,3}(\.\d{1,2})?$/.test(raw)) return null
  const value = Number(raw)
  if (!Number.isFinite(value) || value <= 0 || value > 100) return null
  return Math.round(value * 100) / 100
}

export function isTaxReservePreset(percent: number): percent is (typeof TAX_RESERVE_PRESETS)[number] {
  return TAX_RESERVE_PRESETS.some((preset) => preset === percent)
}

export function formatTaxReservePercent(percent: number): string {
  const rounded = Math.round(percent * 100) / 100
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2).replace(/0$/, "")
}

export function buildPropFirmYearOverview(input: {
  year: number
  expenses: PropFirmExpenseRecord[]
  payouts: PropFirmOverviewPayout[]
  reservePercent: number
}): PropFirmYearOverview {
  const start = `${input.year}-01-01`
  const end = `${input.year}-12-31`
  const propExpenses = input.expenses.filter((expense) => isPropFirmTrackerExpense(expense))
  const expenses = propExpenses.filter((expense) => expense.datePaid >= start && expense.datePaid <= end)
  const payouts = input.payouts.filter(
    (payout) => payout.payoutDate >= start && payout.payoutDate <= end && payout.amountCents > 0
  )

  const firms = new Map<string, PropFirmProfitability>()
  const categories = new Map<PropFirmExpenseType, number>()
  let expenseCents = 0
  let payoutCents = 0

  for (const expense of expenses) {
    expenseCents += expense.totalCostCents
    const key = propFirmKey(expense.propFirmName)
    const row = firms.get(key) ?? emptyFirm(key, expense.propFirmName.trim() || "Prop firm")
    row.spentCents += expense.totalCostCents
    firms.set(key, row)
    categories.set(expense.expenseType, (categories.get(expense.expenseType) ?? 0) + expense.totalCostCents)
  }

  for (const payout of payouts) {
    payoutCents += payout.amountCents
    const label = firmNameForPropPayout({
      accountId: payout.accountId,
      expenses: propExpenses,
      assignedFirmName: payout.assignedFirmName,
      accountName: payout.accountName,
    })
    const key = label ? propFirmKey(label) : UNASSIGNED_FIRM_KEY
    const row = firms.get(key) ?? emptyFirm(key, label ?? UNASSIGNED_PROP_FIRM)
    row.payoutCents += payout.amountCents
    firms.set(key, row)
  }

  const firmRows = [...firms.values()]
    .map((row) => ({
      ...row,
      netCents: row.payoutCents - row.spentCents,
      shortfallCents: Math.max(0, row.spentCents - row.payoutCents),
    }))
    .filter((row) => row.spentCents > 0 || row.payoutCents > 0)
    .sort((a, b) => {
      if (a.key === UNASSIGNED_FIRM_KEY) return 1
      if (b.key === UNASSIGNED_FIRM_KEY) return -1
      if (b.netCents !== a.netCents) return b.netCents - a.netCents
      if (b.payoutCents !== a.payoutCents) return b.payoutCents - a.payoutCents
      return a.label.localeCompare(b.label)
    })

  const identified = firmRows.filter((row) => row.key !== UNASSIGNED_FIRM_KEY)
  const netCents = payoutCents - expenseCents

  return {
    year: input.year,
    payoutCents,
    expenseCents,
    netCents,
    deductibleEstimateCents: expenseCents,
    reserveCents: estimatedTaxReserveCents(netCents, input.reservePercent),
    firms: firmRows,
    mostProfitableFirmKey: identified[0]?.key ?? null,
    byCategory: PROP_FIRM_EXPENSE_TYPES.flatMap((type) => {
      const totalCents = categories.get(type.value) ?? 0
      if (totalCents <= 0) return []
      return [{ key: type.value, label: propFirmExpenseTypeLabel(type.value), totalCents }]
    }),
    spendingByFirm: firmRows
      .filter((row) => row.spentCents > 0)
      .map((row) => ({ key: row.key, label: row.label, totalCents: row.spentCents }))
      .sort((a, b) => b.totalCents - a.totalCents || a.label.localeCompare(b.label)),
    months: monthsForYear(input.year, expenses, payouts),
  }
}

function emptyFirm(key: string, label: string): PropFirmProfitability {
  return { key, label, spentCents: 0, payoutCents: 0, netCents: 0, shortfallCents: 0 }
}

function monthsForYear(
  year: number,
  expenses: PropFirmExpenseRecord[],
  payouts: PropFirmOverviewPayout[]
): PropFirmMonthComparison[] {
  const months = MONTH_LABELS.map((label, index) => {
    const month = String(index + 1).padStart(2, "0")
    return { monthKey: `${year}-${month}`, label, expenseCents: 0, payoutCents: 0 }
  })
  const index = new Map(months.map((month) => [month.monthKey, month]))
  for (const expense of expenses) {
    const bucket = index.get(expense.datePaid.slice(0, 7))
    if (bucket) bucket.expenseCents += expense.totalCostCents
  }
  for (const payout of payouts) {
    const bucket = index.get(payout.payoutDate.slice(0, 7))
    if (bucket) bucket.payoutCents += payout.amountCents
  }
  return months
}

let reserveCache: { userId: string; percent: number } | null = null

export async function loadTaxReservePercent(
  client: SupabaseClient<Database>,
  userId: string,
  options?: { force?: boolean }
): Promise<number> {
  if (!options?.force && reserveCache?.userId === userId) return reserveCache.percent
  const { data, error } = await client
    .from("prop_firm_expense_settings")
    .select("tax_reserve_percent")
    .eq("user_id", userId)
    .maybeSingle()
  if (error || !data) return DEFAULT_TAX_RESERVE_PERCENT
  const percent = parseTaxReservePercent(String(data.tax_reserve_percent)) ?? DEFAULT_TAX_RESERVE_PERCENT
  reserveCache = { userId, percent }
  return percent
}

export async function saveTaxReservePercent(
  client: SupabaseClient<Database>,
  userId: string,
  percent: number
): Promise<string | null> {
  const parsed = parseTaxReservePercent(String(percent))
  if (parsed == null) return "Enter a percentage from 0.01 to 100."
  const { error } = await client.from("prop_firm_expense_settings").upsert(
    {
      user_id: userId,
      tax_reserve_percent: parsed.toFixed(2) as unknown as number,
    },
    { onConflict: "user_id" }
  )
  if (error) return "Couldn't save your tax reserve percentage."
  reserveCache = { userId, percent: parsed }
  return null
}
