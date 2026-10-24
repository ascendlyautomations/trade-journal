import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  occurrenceDates,
  type ExpenseRecurrence,
  isExpenseRecurrence,
} from "./expenseRecurrence.ts"
import { getLocalTodayDateInputValue, isDateAfterToday } from "./tradeDateValidation.ts"

export const PROP_FIRM_EXPENSE_TYPES = [
  { value: "evaluation_purchase", label: "Evaluation" },
  { value: "activation_fee", label: "Activation" },
  { value: "reset_fee", label: "Reset" },
  { value: "subscription_renewal", label: "Renewal" },
  { value: "other", label: "Other" },
] as const

export type PropFirmExpenseType = (typeof PROP_FIRM_EXPENSE_TYPES)[number]["value"]
export type PropFirmExpenseSource = "manual" | "account_purchase"

export const EXPENSE_TRACKER_KINDS = [
  { value: "prop_firm", label: "Prop Firm" },
  { value: "business", label: "Business" },
  { value: "trading_tools", label: "Trading Tools" },
  { value: "other", label: "Other" },
] as const

export type ExpenseTrackerKind = (typeof EXPENSE_TRACKER_KINDS)[number]["value"]

export const PROP_FIRM_EXPENSE_SELECT =
  "id,user_id,prop_firm_name,expense_type,cost_per_account,quantity,total_cost,date_paid,payment_label,notes,account_id,source,tracker_kind,project_label,custom_category,recurrence,created_at,updated_at" as const

const FIRM_NAME_MAX = 120
const LABEL_MAX = 80
const PAYMENT_LABEL_MAX = 80
const NOTES_MAX = 500
const QUANTITY_MAX = 10000
const COST_CENTS_MAX = 99999999999

export type PropFirmExpenseRecord = {
  id: string
  userId: string
  propFirmName: string
  expenseType: PropFirmExpenseType
  costPerAccountCents: number
  quantity: number
  totalCostCents: number
  datePaid: string
  paymentLabel: string | null
  notes: string | null
  accountId: string | null
  source: PropFirmExpenseSource
  trackerKind: ExpenseTrackerKind
  projectLabel: string | null
  customCategory: string | null
  recurrence: ExpenseRecurrence | null
  /** Saved row id. Occurrence rows reuse it when a repeat is opened for edit. */
  seriesId: string
}

export type PropFirmExpenseDraft = {
  trackerKind: ExpenseTrackerKind
  propFirmName: string
  expenseType: PropFirmExpenseType
  projectLabel: string
  customCategory: string
  costDigits: string
  quantityDigits: string
  datePaid: string
  paymentLabel: string
  notes: string
  accountId: string | null
  recurrence: ExpenseRecurrence | ""
}

export type PropFirmExpenseAccountOption = {
  id: string
  name: string
}

type ExpenseInsert = Database["public"]["Tables"]["prop_firm_expenses"]["Insert"]
type ExpenseUpdate = Database["public"]["Tables"]["prop_firm_expenses"]["Update"]

let cacheGeneration = 0
let expenseCache: {
  userId: string
  generation: number
  rows: PropFirmExpenseRecord[]
} | null = null

export function invalidatePropFirmExpenseCache() {
  cacheGeneration += 1
  expenseCache = null
}

export function propFirmExpenseTypeLabel(type: PropFirmExpenseType): string {
  return (
    PROP_FIRM_EXPENSE_TYPES.find((item) => item.value === type)?.label ?? "Other"
  )
}

export function isPropFirmExpenseType(value: string): value is PropFirmExpenseType {
  return PROP_FIRM_EXPENSE_TYPES.some((item) => item.value === value)
}

export function isExpenseTrackerKind(value: string): value is ExpenseTrackerKind {
  return EXPENSE_TRACKER_KINDS.some((item) => item.value === value)
}

export function expenseTrackerKindLabel(kind: ExpenseTrackerKind): string {
  return EXPENSE_TRACKER_KINDS.find((item) => item.value === kind)?.label ?? "Other"
}

export function isPropFirmTrackerExpense(expense: { trackerKind?: ExpenseTrackerKind }): boolean {
  return (expense.trackerKind ?? "prop_firm") === "prop_firm"
}

export function expenseCategoryLabel(expense: PropFirmExpenseRecord): string {
  if (isPropFirmTrackerExpense(expense)) return propFirmExpenseTypeLabel(expense.expenseType)
  return expense.customCategory?.trim() || "Uncategorized"
}

export function expenseProjectLabel(expense: PropFirmExpenseRecord): string {
  if (isPropFirmTrackerExpense(expense)) return expense.propFirmName.trim() || "Prop firm"
  return expense.projectLabel?.trim() || "No project"
}

/** Eval and funded prop accounts can record an optional purchase cost. */
export function accountPurchaseExpenseType(
  category: string | null | undefined,
  mode: string | null | undefined
): "evaluation_purchase" | "activation_fee" | null {
  if (String(category ?? "").trim() !== "Prop Firm") return null
  const normalized = String(mode ?? "").trim().toLowerCase()
  if (normalized === "eval" || normalized === "evaluation") return "evaluation_purchase"
  if (normalized === "funded") return "activation_fee"
  return null
}

export function accountPurchaseIdentity(accountId: string): string {
  return `account_purchase:${accountId}`
}

/** Integer cents. Rejects more than two fractional digits and non-numeric input. */
export function parseMoneyToCents(input: string | number | null | undefined): number | null {
  if (input == null) return null
  const raw =
    typeof input === "number"
      ? trimNumberToCents(input)
      : String(input).trim().replace(/[$,\s]/g, "")
  if (!raw) return null
  const negative = raw.startsWith("-")
  const body = negative ? raw.slice(1) : raw
  if (!/^\d+(\.\d{1,2})?$/.test(body)) return null
  const [whole, frac = ""] = body.split(".")
  const cents = Number(whole) * 100 + Number((frac + "00").slice(0, 2))
  if (!Number.isSafeInteger(cents)) return null
  return negative ? -cents : cents
}

export function decimalToCents(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return parseMoneyToCents(trimNumberToCents(value)) ?? 0
  }
  return parseMoneyToCents(value == null ? "" : String(value)) ?? 0
}

export function centsToDecimalString(cents: number): string {
  const negative = cents < 0
  const abs = Math.abs(Math.trunc(cents))
  const whole = Math.floor(abs / 100)
  const frac = String(abs % 100).padStart(2, "0")
  return `${negative ? "-" : ""}${whole}.${frac}`
}

export function formatCents(cents: number): string {
  const negative = cents < 0
  const abs = Math.abs(Math.trunc(cents))
  const whole = Math.floor(abs / 100).toLocaleString("en-US")
  const frac = String(abs % 100).padStart(2, "0")
  return `${negative ? "-" : ""}$${whole}.${frac}`
}

export function totalCostCents(costPerAccountCents: number, quantity: number): number {
  return Math.trunc(costPerAccountCents) * Math.trunc(quantity)
}

export function sanitizeMoneyInput(value: string): string {
  const cleaned = value.replace(/[$,\s]/g, "")
  if (cleaned === "") return ""
  if (!/^\d*\.?\d{0,2}$/.test(cleaned)) return ""
  return cleaned
}

export function sanitizeQuantityInput(value: string): string {
  return value.replace(/\D/g, "").slice(0, 5)
}

export function emptyPropFirmExpenseDraft(today = getLocalTodayDateInputValue()): PropFirmExpenseDraft {
  return {
    trackerKind: "prop_firm",
    propFirmName: "",
    expenseType: "evaluation_purchase",
    projectLabel: "",
    customCategory: "",
    costDigits: "",
    quantityDigits: "1",
    datePaid: today,
    paymentLabel: "",
    notes: "",
    accountId: null,
    recurrence: "",
  }
}

export function draftFromExpense(expense: PropFirmExpenseRecord): PropFirmExpenseDraft {
  return {
    trackerKind: expense.trackerKind,
    propFirmName: expense.propFirmName,
    expenseType: expense.expenseType,
    projectLabel: expense.projectLabel ?? "",
    customCategory: expense.customCategory ?? "",
    costDigits: centsToDecimalString(expense.costPerAccountCents),
    quantityDigits: String(expense.quantity),
    datePaid: expense.datePaid,
    paymentLabel: expense.paymentLabel ?? "",
    notes: expense.notes ?? "",
    accountId: expense.accountId,
    recurrence: expense.recurrence ?? "",
  }
}

export function validatePropFirmExpenseDraft(
  draft: PropFirmExpenseDraft,
  options?: { today?: string }
): string | null {
  const name = draft.propFirmName.trim()
  const propFirm = (draft.trackerKind ?? "prop_firm") === "prop_firm"
  if (!name) return propFirm ? "Enter the prop firm name." : "Enter a vendor or name."
  if (name.length > FIRM_NAME_MAX) return propFirm ? "Prop firm name is too long." : "Name is too long."
  if (propFirm) {
    if (!isPropFirmExpenseType(draft.expenseType)) return "Choose an expense type."
  } else {
    const category = (draft.customCategory ?? "").trim()
    if (!category) return "Choose or enter a category."
    if (category.length > LABEL_MAX) return "Category is too long."
    if ((draft.projectLabel ?? "").trim().length > LABEL_MAX) return "Business or project label is too long."
  }

  const cost = parseMoneyToCents(draft.costDigits)
  if (cost == null || cost <= 0) return "Enter a cost greater than zero."
  if (cost > COST_CENTS_MAX) return "Cost is too large."

  const quantity = Number(draft.quantityDigits)
  if (!Number.isInteger(quantity) || quantity < 1 || quantity > QUANTITY_MAX) {
    return draft.trackerKind === "prop_firm"
      ? "Enter an account quantity from 1 to 10,000."
      : "Enter a quantity from 1 to 10,000."
  }

  const datePaid = draft.datePaid.trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(datePaid)) return "Choose the purchase date."
  const today = options?.today ?? getLocalTodayDateInputValue()
  if (isDateAfterToday(datePaid, dateFromInput(today))) {
    return "Purchase date cannot be in the future."
  }

  if (draft.paymentLabel.trim().length > PAYMENT_LABEL_MAX) {
    return "Bank or card label is too long."
  }
  if (draft.notes.trim().length > NOTES_MAX) return "Notes are too long."
  return null
}

export type ExpenseBreakdown = { key: string; label: string; totalCents: number }
export type MonthlySpendPoint = { monthKey: string; label: string; totalCents: number }

export type PropFirmExpenseAnalytics = {
  totalSpentCents: number
  totalAccountsPurchased: number
  totalPayoutsCents: number
  netProfitCents: number
  byFirm: ExpenseBreakdown[]
  byCategory: ExpenseBreakdown[]
  monthly: MonthlySpendPoint[]
}

export function summarizePropFirmExpenses(
  expenses: PropFirmExpenseRecord[],
  payoutCents: number,
  now = new Date()
): PropFirmExpenseAnalytics {
  let totalSpentCents = 0
  let totalAccountsPurchased = 0
  const firms = new Map<string, { label: string; totalCents: number }>()
  const categories = new Map<PropFirmExpenseType, number>()

  for (const expense of expenses) {
    totalSpentCents += expense.totalCostCents
    totalAccountsPurchased += expense.quantity
    const firmKey = expense.propFirmName.trim().toLowerCase()
    const firm = firms.get(firmKey) ?? {
      label: expense.propFirmName.trim(),
      totalCents: 0,
    }
    firm.totalCents += expense.totalCostCents
    firms.set(firmKey, firm)
    categories.set(
      expense.expenseType,
      (categories.get(expense.expenseType) ?? 0) + expense.totalCostCents
    )
  }

  return {
    totalSpentCents,
    totalAccountsPurchased,
    totalPayoutsCents: payoutCents,
    netProfitCents: payoutCents - totalSpentCents,
    byFirm: [...firms.values()].sort((a, b) => b.totalCents - a.totalCents || a.label.localeCompare(b.label)).map((row) => ({
      key: row.label,
      label: row.label,
      totalCents: row.totalCents,
    })),
    byCategory: PROP_FIRM_EXPENSE_TYPES.flatMap((type) => {
      const totalCents = categories.get(type.value) ?? 0
      if (totalCents === 0) return []
      return [{ key: type.value, label: type.label, totalCents }]
    }),
    monthly: monthlySpendingTrend(expenses, now),
  }
}

export function filterPropFirmExpenses(
  expenses: PropFirmExpenseRecord[],
  filter: {
    firm?: string
    category?: string
    from?: string
    to?: string
    kind?: string
    project?: string
  }
): PropFirmExpenseRecord[] {
  const firm = filter.firm?.trim().toLowerCase() ?? ""
  const category = filter.category?.trim().toLowerCase() ?? ""
  const from = filter.from?.trim() ?? ""
  const to = filter.to?.trim() ?? ""
  const kind = filter.kind?.trim() ?? ""
  const project = filter.project?.trim().toLowerCase() ?? ""
  return expenses.filter((expense) => {
    if (kind && kind !== "all" && expense.trackerKind !== kind) return false
    if (firm && firm !== "all" && expense.propFirmName.trim().toLowerCase() !== firm) {
      return false
    }
    if (project && project !== "all" && expenseProjectLabel(expense).trim().toLowerCase() !== project) {
      return false
    }
    if (category && category !== "all") {
      if (category.startsWith("custom:")) {
        const custom = (expense.customCategory ?? "").trim().toLowerCase()
        if (custom !== category.slice("custom:".length)) return false
      } else if (!isPropFirmTrackerExpense(expense) || expense.expenseType !== category) {
        return false
      }
    }
    if (from && expense.datePaid < from) return false
    if (to && expense.datePaid > to) return false
    return true
  })
}

export type ExpenseTrackerSummary = {
  totalSpentCents: number
  byKind: ExpenseBreakdown[]
  byCategory: ExpenseBreakdown[]
  byProject: ExpenseBreakdown[]
}

export function summarizeExpenseTracker(expenses: PropFirmExpenseRecord[]): ExpenseTrackerSummary {
  let totalSpentCents = 0
  const kinds = new Map<string, { label: string; totalCents: number }>()
  const categories = new Map<string, { label: string; totalCents: number }>()
  const projects = new Map<string, { label: string; totalCents: number }>()
  for (const expense of expenses) {
    totalSpentCents += expense.totalCostCents
    addBreakdown(kinds, expense.trackerKind, expenseTrackerKindLabel(expense.trackerKind), expense.totalCostCents)
    const category = expenseCategoryLabel(expense)
    addBreakdown(categories, category.toLowerCase(), category, expense.totalCostCents)
    const project = expenseProjectLabel(expense)
    addBreakdown(projects, project.toLowerCase(), project, expense.totalCostCents)
  }
  return {
    totalSpentCents,
    byKind: sortedBreakdown(kinds),
    byCategory: sortedBreakdown(categories),
    byProject: sortedBreakdown(projects),
  }
}

function addBreakdown(
  buckets: Map<string, { label: string; totalCents: number }>,
  key: string,
  label: string,
  cents: number
) {
  const row = buckets.get(key) ?? { label, totalCents: 0 }
  row.totalCents += cents
  buckets.set(key, row)
}

function sortedBreakdown(buckets: Map<string, { label: string; totalCents: number }>): ExpenseBreakdown[] {
  return [...buckets.entries()]
    .map(([key, row]) => ({ key, label: row.label, totalCents: row.totalCents }))
    .sort((a, b) => b.totalCents - a.totalCents || a.label.localeCompare(b.label))
}

export function monthlySpendingTrend(
  expenses: Array<{ datePaid: string; totalCostCents: number }>,
  now = new Date()
): MonthlySpendPoint[] {
  const cursor = new Date(now.getFullYear(), now.getMonth(), 1)
  const months: MonthlySpendPoint[] = []
  for (let offset = 11; offset >= 0; offset -= 1) {
    const date = new Date(cursor.getFullYear(), cursor.getMonth() - offset, 1)
    const monthKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`
    months.push({
      monthKey,
      label: date.toLocaleDateString("en-US", { month: "short" }),
      totalCents: 0,
    })
  }
  const index = new Map(months.map((month) => [month.monthKey, month]))
  for (const expense of expenses) {
    const bucket = index.get(expense.datePaid.slice(0, 7))
    if (bucket) bucket.totalCents += expense.totalCostCents
  }
  return months
}

export function sumPropPayoutCents(amounts: Array<number | string | null | undefined>): number {
  return amounts.reduce<number>((sum, amount) => sum + decimalToCents(amount), 0)
}

export async function loadPropFirmExpenses(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<{ expenses: PropFirmExpenseRecord[]; error: string | null }> {
  if (
    !options?.force &&
    expenseCache &&
    expenseCache.userId === userId &&
    expenseCache.generation === cacheGeneration
  ) {
    return { expenses: expenseCache.rows, error: null }
  }

  const { data, error } = await client
    .from("prop_firm_expenses")
    .select(PROP_FIRM_EXPENSE_SELECT)
    .eq("user_id", userId)
    .order("date_paid", { ascending: false })
    .order("id", { ascending: false })

  if (error) return { expenses: [], error: error.message }
  const rows = (data ?? [])
    .map((row) => mapExpenseRow(row as Record<string, unknown>))
    .filter((row): row is PropFirmExpenseRecord => row != null)
  expenseCache = { userId, generation: cacheGeneration, rows }
  return { expenses: rows, error: null }
}

export async function fetchAccountPurchaseCostInput(
  client: SupabaseClient,
  userId: string,
  accountId: string
): Promise<{ cost: string; purchaseDate: string }> {
  const { data, error } = await client
    .from("prop_firm_expenses")
    .select("cost_per_account,date_paid")
    .eq("user_id", userId)
    .eq("account_id", accountId)
    .eq("source", "account_purchase")
    .maybeSingle()
  if (error || !data) return { cost: "", purchaseDate: "" }
  const cents = decimalToCents(data.cost_per_account)
  const purchaseDate = String(data.date_paid ?? "").slice(0, 10)
  return {
    cost: cents > 0 ? centsToDecimalString(cents) : "",
    purchaseDate: /^\d{4}-\d{2}-\d{2}$/.test(purchaseDate) ? purchaseDate : "",
  }
}

export async function createPropFirmExpense(
  client: SupabaseClient,
  userId: string,
  draft: PropFirmExpenseDraft
): Promise<{ expense: PropFirmExpenseRecord | null; error: string | null }> {
  const invalid = validatePropFirmExpenseDraft(draft)
  if (invalid) return { expense: null, error: invalid }
  const cost = parseMoneyToCents(draft.costDigits)
  if (cost == null) return { expense: null, error: "Enter a cost greater than zero." }

  const body = expenseWriteFields(draft, {
    user_id: userId,
    account_id: draft.trackerKind === "prop_firm" ? draft.accountId || null : null,
    source: "manual",
  }) as unknown as ExpenseInsert

  const { data, error } = await client
    .from("prop_firm_expenses")
    .insert(body)
    .select(PROP_FIRM_EXPENSE_SELECT)
    .single()

  if (error) return { expense: null, error: expenseWriteError(error.message, error.code) }
  invalidatePropFirmExpenseCache()
  return { expense: mapExpenseRow(data as Record<string, unknown>), error: null }
}

export async function updatePropFirmExpense(
  client: SupabaseClient,
  userId: string,
  expenseId: string,
  draft: PropFirmExpenseDraft,
  source: PropFirmExpenseSource
): Promise<{ expense: PropFirmExpenseRecord | null; error: string | null }> {
  const invalid = validatePropFirmExpenseDraft(draft)
  if (invalid) return { expense: null, error: invalid }
  const cost = parseMoneyToCents(draft.costDigits)
  if (cost == null) return { expense: null, error: "Enter a cost greater than zero." }

  const body = expenseWriteFields(draft, {
    account_id:
      source === "account_purchase" || draft.trackerKind !== "prop_firm"
        ? source === "account_purchase"
          ? undefined
          : null
        : draft.accountId || null,
  }) as unknown as ExpenseUpdate

  const { data, error } = await client
    .from("prop_firm_expenses")
    .update(body)
    .eq("id", expenseId)
    .eq("user_id", userId)
    .select(PROP_FIRM_EXPENSE_SELECT)
    .single()

  if (error) return { expense: null, error: expenseWriteError(error.message, error.code) }
  invalidatePropFirmExpenseCache()
  return { expense: mapExpenseRow(data as Record<string, unknown>), error: null }
}

export async function deletePropFirmExpense(
  client: SupabaseClient,
  userId: string,
  expenseId: string
): Promise<{ error: string | null }> {
  const { error } = await client
    .from("prop_firm_expenses")
    .delete()
    .eq("id", expenseId)
    .eq("user_id", userId)
  if (error) return { error: error.message }
  invalidatePropFirmExpenseCache()
  return { error: null }
}

export async function syncPropFirmAccountPurchaseExpense(
  client: SupabaseClient,
  userId: string,
  accountId: string,
  input: {
    name: string
    category: string
    mode: string | null
    purchaseCost?: string | null
    datePaid?: string | null
  }
): Promise<{ ok: true; recorded: boolean } | { ok: false; message: string }> {
  const expenseType = accountPurchaseExpenseType(input.category, input.mode)
  const cents = parseMoneyToCents(input.purchaseCost ?? "")
  if (!expenseType || cents == null || cents <= 0) {
    return { ok: true, recorded: false }
  }
  if (cents > COST_CENTS_MAX) {
    return { ok: false, message: "Account purchase cost is too large." }
  }
  const datePaid = input.datePaid?.trim() || getLocalTodayDateInputValue()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(datePaid) || isDateAfterToday(datePaid, dateFromInput(getLocalTodayDateInputValue()))) {
    return { ok: false, message: "Purchase date cannot be in the future." }
  }

  const { data, error } = await client.rpc("upsert_prop_firm_account_purchase_expense", {
    p_account_id: accountId,
    p_user_id: userId,
    p_cost_per_account: centsToDecimalString(cents) as unknown as number,
    p_prop_firm_name: input.name.trim(),
    p_expense_type: expenseType,
    p_date_paid: datePaid,
  })

  if (error) {
    return { ok: false, message: error.message || "Couldn't record the account purchase cost." }
  }
  if (!data) {
    return { ok: false, message: "Couldn't record the account purchase cost." }
  }
  invalidatePropFirmExpenseCache()
  return { ok: true, recorded: true }
}

function mapExpenseRow(row: Record<string, unknown> | null): PropFirmExpenseRecord | null {
  if (!row) return null
  const id = String(row.id ?? "").trim()
  const type = String(row.expense_type ?? "")
  if (!id || !isPropFirmExpenseType(type)) return null
  const costPerAccountCents = decimalToCents(row.cost_per_account)
  const quantity = Number(row.quantity) || 0
  const storedTotal = decimalToCents(row.total_cost)
  const source = row.source === "account_purchase" ? "account_purchase" : "manual"
  return {
    id,
    userId: String(row.user_id ?? ""),
    propFirmName: String(row.prop_firm_name ?? "").trim(),
    expenseType: type,
    costPerAccountCents,
    quantity,
    totalCostCents: storedTotal > 0 ? storedTotal : totalCostCents(costPerAccountCents, quantity),
    datePaid: String(row.date_paid ?? "").slice(0, 10),
    paymentLabel: row.payment_label != null ? String(row.payment_label) : null,
    notes: row.notes != null ? String(row.notes) : null,
    accountId: row.account_id != null ? String(row.account_id) : null,
    source,
    trackerKind: isExpenseTrackerKind(String(row.tracker_kind ?? ""))
      ? (row.tracker_kind as ExpenseTrackerKind)
      : "prop_firm",
    projectLabel: row.project_label != null ? String(row.project_label).trim() || null : null,
    customCategory: row.custom_category != null ? String(row.custom_category).trim() || null : null,
    recurrence: isExpenseRecurrence(String(row.recurrence ?? ""))
      ? (row.recurrence as ExpenseRecurrence)
      : null,
    seriesId: id,
  }
}

export function expandPropFirmExpenses(
  expenses: PropFirmExpenseRecord[],
  through = getLocalTodayDateInputValue()
): PropFirmExpenseRecord[] {
  return expenses.flatMap((expense) => {
    const dates = occurrenceDates(expense.datePaid, expense.recurrence, through)
    if (dates.length <= 1) return [{ ...expense, seriesId: expense.seriesId || expense.id }]
    return dates.map((datePaid) => ({
      ...expense,
      id: `${expense.id}:${datePaid}`,
      seriesId: expense.id,
      datePaid,
    }))
  })
}

function expenseWriteFields(
  draft: PropFirmExpenseDraft,
  extra: Record<string, unknown>
): Record<string, unknown> {
  const cost = parseMoneyToCents(draft.costDigits) ?? 0
  const propFirm = draft.trackerKind === "prop_firm"
  return {
    ...extra,
    tracker_kind: draft.trackerKind,
    prop_firm_name: draft.propFirmName.trim(),
    expense_type: propFirm ? draft.expenseType : "other",
    project_label: propFirm ? null : draft.projectLabel.trim() || null,
    custom_category: propFirm ? null : draft.customCategory.trim() || null,
    cost_per_account: centsToDecimalString(cost),
    quantity: Number(draft.quantityDigits),
    date_paid: draft.datePaid,
    payment_label: draft.paymentLabel.trim() || null,
    notes: draft.notes.trim() || null,
    recurrence: isExpenseRecurrence(draft.recurrence) ? draft.recurrence : null,
  }
}

export async function loadExpenseCategories(
  client: SupabaseClient,
  userId: string
): Promise<string[]> {
  const { data, error } = await client
    .from("expense_categories")
    .select("name")
    .eq("user_id", userId)
    .order("name", { ascending: true })
  if (error || !data) return []
  return data.map((row) => String(row.name ?? "").trim()).filter(Boolean)
}

export async function saveExpenseCategory(
  client: SupabaseClient,
  userId: string,
  name: string
): Promise<string | null> {
  const trimmed = name.trim()
  if (!trimmed || trimmed.length > LABEL_MAX) return "Enter a category up to 80 characters."
  const { error } = await client.from("expense_categories").upsert(
    { user_id: userId, name: trimmed } as Database["public"]["Tables"]["expense_categories"]["Insert"],
    { onConflict: "user_id,name" }
  )
  return error ? error.message : null
}

function expenseWriteError(message: string, code?: string): string {
  if (code === "23505") {
    return "That account already has a purchase expense."
  }
  return message || "Couldn't save that expense."
}

function trimNumberToCents(value: number): string {
  const negative = value < 0
  const abs = Math.abs(value)
  const cents = Math.round((abs + Number.EPSILON) * 100)
  return `${negative ? "-" : ""}${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, "0")}`
}

function dateFromInput(day: string): Date {
  const [year, month, date] = day.split("-").map(Number)
  return new Date(year, (month || 1) - 1, date || 1, 12, 0, 0, 0)
}
