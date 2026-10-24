import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  expenseRecurrenceLabel,
  isExpenseRecurrence,
  occurrenceDates,
  type ExpenseRecurrence,
} from "./expenseRecurrence.ts"
import { decimalToCents, formatCents, parseMoneyToCents, centsToDecimalString } from "./propFirmExpenses.ts"
import { payoutCalendarDay } from "./propFirmExpenseTaxExport.ts"
import { payoutHistoryItemHref, type PayoutHistoryAccount, type PayoutHistoryItem } from "./payoutHistory.ts"
import { getLocalTodayDateInputValue, isDateAfterToday } from "./tradeDateValidation.ts"

export const TRACKER_INCOME_KINDS = [
  { value: "withdrawal", label: "Withdrawal" },
  { value: "business", label: "Business income" },
] as const

export type TrackerIncomeKind = (typeof TRACKER_INCOME_KINDS)[number]["value"]

export const TRACKER_INCOME_SELECT =
  "id,user_id,income_kind,name,project_label,amount,date_received,payment_label,notes,recurrence,created_at,updated_at" as const

const NAME_MAX = 120
const LABEL_MAX = 80
const NOTES_MAX = 500
const AMOUNT_CENTS_MAX = 99999999999

export type TrackerIncomeRecord = {
  id: string
  userId: string
  incomeKind: TrackerIncomeKind
  name: string
  projectLabel: string | null
  amountCents: number
  dateReceived: string
  paymentLabel: string | null
  notes: string | null
  recurrence: ExpenseRecurrence | null
  seriesId: string
  source: "recorded" | "withdrawal"
  href: string | null
}

export type TrackerIncomeDraft = {
  incomeKind: TrackerIncomeKind
  name: string
  projectLabel: string
  amountDigits: string
  dateReceived: string
  paymentLabel: string
  notes: string
  recurrence: ExpenseRecurrence | ""
}

type IncomeInsert = Database["public"]["Tables"]["tracker_income"]["Insert"]
type IncomeUpdate = Database["public"]["Tables"]["tracker_income"]["Update"]

let cacheGeneration = 0
let incomeCache: { userId: string; generation: number; rows: TrackerIncomeRecord[] } | null = null

export function invalidateTrackerIncomeCache() {
  cacheGeneration += 1
  incomeCache = null
}

export function trackerIncomeKindLabel(kind: TrackerIncomeKind): string {
  return TRACKER_INCOME_KINDS.find((item) => item.value === kind)?.label ?? "Income"
}

export function emptyTrackerIncomeDraft(today = getLocalTodayDateInputValue()): TrackerIncomeDraft {
  return {
    incomeKind: "business",
    name: "",
    projectLabel: "",
    amountDigits: "",
    dateReceived: today,
    paymentLabel: "",
    notes: "",
    recurrence: "",
  }
}

export function draftFromTrackerIncome(income: TrackerIncomeRecord): TrackerIncomeDraft {
  return {
    incomeKind: income.incomeKind,
    name: income.name,
    projectLabel: income.projectLabel ?? "",
    amountDigits: centsToDecimalString(income.amountCents),
    dateReceived: income.dateReceived,
    paymentLabel: income.paymentLabel ?? "",
    notes: income.notes ?? "",
    recurrence: income.recurrence ?? "",
  }
}

export function validateTrackerIncomeDraft(
  draft: TrackerIncomeDraft,
  options?: { today?: string }
): string | null {
  const name = draft.name.trim()
  if (!name) return draft.incomeKind === "withdrawal" ? "Enter where this withdrawal came from." : "Enter who paid you."
  if (name.length > NAME_MAX) return "Name is too long."
  if (draft.incomeKind === "business" && draft.projectLabel.trim().length > LABEL_MAX) {
    return "Business or project label is too long."
  }
  const amount = parseMoneyToCents(draft.amountDigits)
  if (amount == null || amount <= 0) return "Enter an amount greater than zero."
  if (amount > AMOUNT_CENTS_MAX) return "Amount is too large."
  const dateReceived = draft.dateReceived.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateReceived)) return "Choose the date received."
  const today = options?.today ?? getLocalTodayDateInputValue()
  if (isDateAfterToday(dateReceived, dateFromInput(today))) return "Date received cannot be in the future."
  if (draft.paymentLabel.trim().length > LABEL_MAX) return "Bank or card label is too long."
  if (draft.notes.trim().length > NOTES_MAX) return "Notes are too long."
  if (draft.recurrence && !isExpenseRecurrence(draft.recurrence)) return "Choose how often this repeats."
  return null
}

export function trackerIncomeFromWithdrawals(
  items: PayoutHistoryItem[],
  accountsById: Record<string, PayoutHistoryAccount | undefined>
): TrackerIncomeRecord[] {
  return items.flatMap((item) => {
    if (item.amount <= 0) return []
    const dateReceived = payoutCalendarDay(item.payoutDate, item.dateMs)
    if (!dateReceived) return []
    const accountName = accountsById[item.accountId]?.name?.trim()
    const fromAchievement =
      item.source === "achievementProp" || item.source === "achievementLive"
    return [{
      id: `withdrawal:${item.id}`,
      userId: "",
      incomeKind: "withdrawal" as const,
      name: accountName || (fromAchievement ? item.note?.trim() : "") || "Withdrawal",
      projectLabel: null,
      amountCents: decimalToCents(item.amount),
      dateReceived,
      paymentLabel: null,
      notes: fromAchievement ? null : item.note,
      recurrence: null,
      seriesId: item.id,
      source: "withdrawal" as const,
      href: payoutHistoryItemHref(item.id),
    }]
  })
}

export function expandTrackerIncome(
  rows: TrackerIncomeRecord[],
  through = getLocalTodayDateInputValue()
): TrackerIncomeRecord[] {
  return rows.flatMap((income) => {
    const dates = occurrenceDates(income.dateReceived, income.recurrence, through)
    if (dates.length <= 1) return [{ ...income, seriesId: income.seriesId || income.id }]
    return dates.map((dateReceived) => ({
      ...income,
      id: `${income.id}:${dateReceived}`,
      seriesId: income.id,
      dateReceived,
    }))
  })
}

export type MoneyTrackerSnapshot = {
  incomeCents: number
  expenseCents: number
  netCents: number
  withdrawalCents: number
  businessCents: number
}

export function summarizeMoneyTracker(input: {
  expensesCents: number[]
  income: Array<Pick<TrackerIncomeRecord, "incomeKind" | "amountCents">>
}): MoneyTrackerSnapshot {
  const expenseCents = input.expensesCents.reduce((sum, cents) => sum + cents, 0)
  let withdrawalCents = 0
  let businessCents = 0
  for (const row of input.income) {
    if (row.incomeKind === "withdrawal") withdrawalCents += row.amountCents
    else businessCents += row.amountCents
  }
  const incomeCents = withdrawalCents + businessCents
  return {
    incomeCents,
    expenseCents,
    netCents: incomeCents - expenseCents,
    withdrawalCents,
    businessCents,
  }
}

export function incomeHistorySubtitle(income: TrackerIncomeRecord): string {
  const repeat = expenseRecurrenceLabel(income.recurrence)
  return [
    trackerIncomeKindLabel(income.incomeKind),
    income.incomeKind === "business" ? income.projectLabel?.trim() || "No project" : null,
    repeat,
    income.dateReceived,
    income.paymentLabel,
    income.source === "withdrawal" ? "From withdrawals" : null,
  ]
    .filter(Boolean)
    .join(" · ")
}

export function formatIncomeAmount(cents: number): string {
  return formatCents(cents)
}

export async function loadTrackerIncome(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<{ income: TrackerIncomeRecord[]; error: string | null }> {
  if (
    !options?.force &&
    incomeCache &&
    incomeCache.userId === userId &&
    incomeCache.generation === cacheGeneration
  ) {
    return { income: incomeCache.rows, error: null }
  }
  const { data, error } = await client
    .from("tracker_income")
    .select(TRACKER_INCOME_SELECT)
    .eq("user_id", userId)
    .order("date_received", { ascending: false })
    .order("id", { ascending: false })
  if (error) return { income: [], error: error.message }
  const rows = (data ?? [])
    .map((row) => mapIncomeRow(row as Record<string, unknown>))
    .filter((row): row is TrackerIncomeRecord => row != null)
  incomeCache = { userId, generation: cacheGeneration, rows }
  return { income: rows, error: null }
}

export async function createTrackerIncome(
  client: SupabaseClient,
  userId: string,
  draft: TrackerIncomeDraft
): Promise<{ income: TrackerIncomeRecord | null; error: string | null }> {
  const invalid = validateTrackerIncomeDraft(draft)
  if (invalid) return { income: null, error: invalid }
  const amount = parseMoneyToCents(draft.amountDigits)
  if (amount == null) return { income: null, error: "Enter an amount greater than zero." }
  const body = incomeWriteFields(draft, { user_id: userId, amount }) as unknown as IncomeInsert
  const { data, error } = await client.from("tracker_income").insert(body).select(TRACKER_INCOME_SELECT).single()
  if (error) return { income: null, error: error.message }
  invalidateTrackerIncomeCache()
  return { income: mapIncomeRow(data as Record<string, unknown>), error: null }
}

export async function updateTrackerIncome(
  client: SupabaseClient,
  userId: string,
  incomeId: string,
  draft: TrackerIncomeDraft
): Promise<{ income: TrackerIncomeRecord | null; error: string | null }> {
  const invalid = validateTrackerIncomeDraft(draft)
  if (invalid) return { income: null, error: invalid }
  const amount = parseMoneyToCents(draft.amountDigits)
  if (amount == null) return { income: null, error: "Enter an amount greater than zero." }
  const body = incomeWriteFields(draft, { amount }) as unknown as IncomeUpdate
  const { data, error } = await client
    .from("tracker_income")
    .update(body)
    .eq("id", incomeId)
    .eq("user_id", userId)
    .select(TRACKER_INCOME_SELECT)
    .single()
  if (error) return { income: null, error: error.message }
  invalidateTrackerIncomeCache()
  return { income: mapIncomeRow(data as Record<string, unknown>), error: null }
}

export async function deleteTrackerIncome(
  client: SupabaseClient,
  userId: string,
  incomeId: string
): Promise<{ error: string | null }> {
  const { error } = await client.from("tracker_income").delete().eq("id", incomeId).eq("user_id", userId)
  if (error) return { error: error.message }
  invalidateTrackerIncomeCache()
  return { error: null }
}

function incomeWriteFields(draft: TrackerIncomeDraft, extra: Record<string, unknown>): Record<string, unknown> {
  const amount = parseMoneyToCents(draft.amountDigits) ?? 0
  return {
    ...extra,
    income_kind: draft.incomeKind,
    name: draft.name.trim(),
    project_label: draft.incomeKind === "business" ? draft.projectLabel.trim() || null : null,
    amount: centsToDecimalString(amount),
    date_received: draft.dateReceived,
    payment_label: draft.paymentLabel.trim() || null,
    notes: draft.notes.trim() || null,
    recurrence: isExpenseRecurrence(draft.recurrence) ? draft.recurrence : null,
  }
}

function mapIncomeRow(row: Record<string, unknown> | null): TrackerIncomeRecord | null {
  if (!row) return null
  const id = String(row.id ?? "").trim()
  const kind = String(row.income_kind ?? "")
  if (!id || (kind !== "withdrawal" && kind !== "business")) return null
  return {
    id,
    userId: String(row.user_id ?? ""),
    incomeKind: kind,
    name: String(row.name ?? "").trim(),
    projectLabel: row.project_label != null ? String(row.project_label).trim() || null : null,
    amountCents: decimalToCents(row.amount),
    dateReceived: String(row.date_received ?? "").slice(0, 10),
    paymentLabel: row.payment_label != null ? String(row.payment_label) : null,
    notes: row.notes != null ? String(row.notes) : null,
    recurrence: isExpenseRecurrence(String(row.recurrence ?? ""))
      ? (row.recurrence as ExpenseRecurrence)
      : null,
    seriesId: id,
    source: "recorded",
    href: null,
  }
}

function dateFromInput(day: string): Date {
  const [year, month, date] = day.split("-").map(Number)
  return new Date(year, (month || 1) - 1, date || 1, 12, 0, 0, 0)
}
