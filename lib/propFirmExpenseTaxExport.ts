import {
  centsToDecimalString,
  expenseCategoryLabel,
  expenseTrackerKindLabel,
  propFirmExpenseTypeLabel,
} from "./propFirmExpenses.ts"
import type { PropFirmExpenseRecord } from "./propFirmExpenses.ts"

export type TaxExportPayout = {
  payoutDate: string
  propFirmName: string
  amountCents: number
}

const DISCLAIMER =
  "Financial tracking record for the selected period. Potentially deductible expenses are an unverified estimate equal to total recorded expenses. This file does not determine tax treatment or tax liability. Any estimated tax reserve is a budgeting estimate, not a tax calculation or tax liability."

export const UNASSIGNED_PROP_FIRM = "Unassigned"

export function propFirmKey(name: string): string {
  return name.trim().toLowerCase()
}

/** A firm name recorded on that account's purchase expense, or one shared linked expense. */
export function attributedPropFirmName(
  accountId: string,
  expenses: PropFirmExpenseRecord[]
): string | null {
  const purchase = expenses.find(
    (expense) =>
      expense.accountId === accountId &&
      expense.source === "account_purchase" &&
      expense.propFirmName.trim()
  )
  if (purchase) return purchase.propFirmName.trim()
  const linked = expenses.filter(
    (expense) => expense.accountId === accountId && expense.propFirmName.trim()
  )
  if (linked.length === 0) return null
  const keys = new Set(linked.map((expense) => propFirmKey(expense.propFirmName)))
  if (keys.size === 1) return linked[0].propFirmName.trim()
  return null
}

export function propFirmNameForPayoutAccount(
  accountId: string,
  expenses: PropFirmExpenseRecord[],
  accountName?: string | null
): string {
  return (
    firmNameForPropPayout({ accountId, expenses, accountName }) ?? UNASSIGNED_PROP_FIRM
  )
}

/** Same size-stripping rule as `inferPropFirmName` in propfirmPayoutCycles.ts. */
export function propFirmNameFromAccount(accountName: string | null | undefined): string | null {
  const name = String(accountName ?? "").trim()
  if (!name) return null
  const withoutSize = name.replace(/\s+\$?[\d,]+(?:\.\d+)?\s*[kK]?$/i, "").trim()
  const firm = withoutSize || name
  return firm || null
}

/** An explicit payout assignment wins, then a linked expense, then the account name. */
export function firmNameForPropPayout(input: {
  accountId: string | null
  expenses: PropFirmExpenseRecord[]
  assignedFirmName?: string | null
  accountName?: string | null
}): string | null {
  const assigned = input.assignedFirmName?.trim()
  if (assigned) return assigned
  if (input.accountId) {
    const linked = attributedPropFirmName(input.accountId, input.expenses)
    if (linked) return linked
  }
  return propFirmNameFromAccount(input.accountName)
}

export function estimatedTaxReserveCents(netCents: number, percent: number): number {
  if (!Number.isFinite(netCents) || netCents <= 0) return 0
  if (!Number.isFinite(percent) || percent <= 0 || percent > 100) return 0
  const hundredths = Math.round(percent * 100)
  return Math.round((netCents * hundredths) / 10000)
}

function percentLabel(percent: number): string {
  const rounded = Math.round(percent * 100) / 100
  if (Number.isInteger(rounded)) return String(rounded)
  return rounded.toFixed(2).replace(/0$/, "")
}

export function taxYearPeriod(year: number): { start: string; end: string } | null {
  if (!Number.isInteger(year) || year < 2000 || year > 2100) return null
  return { start: `${year}-01-01`, end: `${year}-12-31` }
}

export function taxCustomPeriod(from: string, to: string): { start: string; end: string } | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) return null
  if (from > to) return null
  return { start: from, end: to }
}

export function payoutCalendarDay(payoutDate: string | null | undefined, dateMs: number): string {
  const ledger = payoutDate?.slice(0, 10) ?? ""
  if (/^\d{4}-\d{2}-\d{2}$/.test(ledger)) return ledger
  if (!Number.isFinite(dateMs) || dateMs <= 0) return ""
  const date = new Date(dateMs)
  const year = date.getUTCFullYear()
  const month = String(date.getUTCMonth() + 1).padStart(2, "0")
  const day = String(date.getUTCDate()).padStart(2, "0")
  return `${year}-${month}-${day}`
}

export function taxExportFilename(start: string, end: string): string {
  if (start.endsWith("-01-01") && end.endsWith("-12-31") && start.slice(0, 4) === end.slice(0, 4)) {
    return `tradetraxs-prop-firm-expenses-${start.slice(0, 4)}.csv`
  }
  return `tradetraxs-prop-firm-expenses-${start}-to-${end}.csv`
}

export function buildPropFirmTaxCsv(input: {
  periodStart: string
  periodEnd: string
  expenses: PropFirmExpenseRecord[]
  payouts: TaxExportPayout[]
  reservePercent?: number | null
}): string {
  const expenses = input.expenses
    .filter((expense) => inPeriod(expense.datePaid, input.periodStart, input.periodEnd))
    .slice()
    .sort((a, b) => a.datePaid.localeCompare(b.datePaid) || a.propFirmName.localeCompare(b.propFirmName))
  const payouts = input.payouts
    .filter((payout) => inPeriod(payout.payoutDate, input.periodStart, input.periodEnd))
    .slice()
    .sort((a, b) => a.payoutDate.localeCompare(b.payoutDate) || a.propFirmName.localeCompare(b.propFirmName))

  const expenseTotal = expenses.reduce((sum, expense) => sum + expense.totalCostCents, 0)
  const payoutTotal = payouts.reduce((sum, payout) => sum + payout.amountCents, 0)

  const lines = [
    row([text("TradeTraxs Prop Firm Expense Tracker")]),
    row([text("Disclaimer"), text(DISCLAIMER)]),
    row([text("Period Start"), value(input.periodStart)]),
    row([text("Period End"), value(input.periodEnd)]),
    row([]),
    row([text("Summary")]),
    row([text("Total Recorded Expenses"), value(centsToDecimalString(expenseTotal))]),
    row([text("Total Recorded Payouts"), value(centsToDecimalString(payoutTotal))]),
    row([text("Net Payouts After Expenses"), value(centsToDecimalString(payoutTotal - expenseTotal))]),
    row([
      text("Potentially Deductible Expenses (unverified estimate)"),
      value(centsToDecimalString(expenseTotal)),
    ]),
    ...(input.reservePercent == null
      ? []
      : [
          row([
            text(`Estimated Tax Reserve (${percentLabel(input.reservePercent)}% budgeting estimate)`),
            value(
              centsToDecimalString(
                estimatedTaxReserveCents(payoutTotal - expenseTotal, input.reservePercent)
              )
            ),
          ]),
        ]),
    row([]),
    row([text("Expenses")]),
    row([
      text("Purchase Date"),
      text("Prop Firm Name"),
      text("Expense Type"),
      text("Bank/Card Paid With"),
      text("Cost Per Account"),
      text("Quantity"),
      text("Total Cost"),
    ]),
    ...expenses.map((expense) =>
      row([
        value(expense.datePaid),
        text(expense.propFirmName),
        text(propFirmExpenseTypeLabel(expense.expenseType)),
        text(expense.paymentLabel ?? ""),
        value(centsToDecimalString(expense.costPerAccountCents)),
        value(String(expense.quantity)),
        value(centsToDecimalString(expense.totalCostCents)),
      ])
    ),
    row([]),
    row([text("Payouts")]),
    row([text("Payout Date"), text("Prop Firm Name"), text("Amount")]),
    ...payouts.map((payout) =>
      row([
        value(payout.payoutDate),
        text(payout.propFirmName),
        value(centsToDecimalString(payout.amountCents)),
      ])
    ),
  ]

  return `\uFEFF${lines.join("\r\n")}\r\n`
}

export function buildExpenseTrackerCsv(input: {
  periodStart: string
  periodEnd: string
  expenses: PropFirmExpenseRecord[]
  payouts: TaxExportPayout[]
  kinds: Array<PropFirmExpenseRecord["trackerKind"]>
  projectKey?: string | null
  reservePercent?: number | null
}): { csv: string; filename: string } {
  const kinds = new Set(input.kinds)
  const project = input.projectKey?.trim().toLowerCase() ?? ""
  const expenses = input.expenses.filter((expense) => {
    if (!kinds.has(expense.trackerKind)) return false
    if (project && project !== "all") {
      const label = (expense.projectLabel ?? expense.propFirmName).trim().toLowerCase()
      if (label !== project) return false
    }
    return inPeriod(expense.datePaid, input.periodStart, input.periodEnd)
  })
  const propOnly = kinds.size === 1 && kinds.has("prop_firm") && (!project || project === "all")
  if (propOnly) {
    return {
      csv: buildPropFirmTaxCsv({
        periodStart: input.periodStart,
        periodEnd: input.periodEnd,
        expenses,
        payouts: input.payouts,
        reservePercent: input.reservePercent,
      }),
      filename: taxExportFilename(input.periodStart, input.periodEnd),
    }
  }
  const includePayouts = kinds.has("prop_firm")
  const payouts = includePayouts
    ? input.payouts.filter((payout) => inPeriod(payout.payoutDate, input.periodStart, input.periodEnd))
    : []
  const expenseTotal = expenses.reduce((sum, expense) => sum + expense.totalCostCents, 0)
  const payoutTotal = payouts.reduce((sum, payout) => sum + payout.amountCents, 0)
  const lines = [
    row([text("TradeTraxs Expense Tracker")]),
    row([
      text("Disclaimer"),
      text(
        "Financial tracking record for the selected period. Totals are recorded expenses and, when prop firm rows are included, recorded prop firm payouts. This file does not determine tax treatment, deductions, or tax liability."
      ),
    ]),
    row([text("Period Start"), value(input.periodStart)]),
    row([text("Period End"), value(input.periodEnd)]),
    row([]),
    row([text("Summary")]),
    row([text("Total Recorded Expenses"), value(centsToDecimalString(expenseTotal))]),
    ...(includePayouts
      ? [
          row([text("Total Recorded Prop Firm Payouts"), value(centsToDecimalString(payoutTotal))]),
          row([text("Net Prop Firm Payouts After Prop Firm Expenses"), value(centsToDecimalString(payoutTotal - expenses.filter((expense) => expense.trackerKind === "prop_firm").reduce((sum, expense) => sum + expense.totalCostCents, 0)))]),
        ]
      : []),
    row([]),
    row([text("Expenses")]),
    row([
      text("Purchase Date"),
      text("Expense Type"),
      text("Name"),
      text("Business/Project"),
      text("Category"),
      text("Bank/Card Paid With"),
      text("Amount"),
      text("Quantity"),
      text("Total Cost"),
    ]),
    ...expenses.map((expense) =>
      row([
        value(expense.datePaid),
        text(expenseTrackerKindLabel(expense.trackerKind)),
        text(expense.propFirmName),
        text(expense.projectLabel ?? ""),
        text(expenseCategoryLabel(expense)),
        text(expense.paymentLabel ?? ""),
        value(centsToDecimalString(expense.costPerAccountCents)),
        value(String(expense.quantity)),
        value(centsToDecimalString(expense.totalCostCents)),
      ])
    ),
  ]
  if (includePayouts) {
    lines.push(
      row([]),
      row([text("Payouts")]),
      row([text("Payout Date"), text("Prop Firm Name"), text("Amount")]),
      ...payouts.map((payout) =>
        row([
          value(payout.payoutDate),
          text(payout.propFirmName),
          value(centsToDecimalString(payout.amountCents)),
        ])
      )
    )
  }
  const filename = `tradetraxs-expenses-${input.periodStart}-to-${input.periodEnd}.csv`
  return { csv: `\uFEFF${lines.join("\r\n")}\r\n`, filename }
}

export function downloadPropFirmTaxCsv(filename: string, csv: string) {
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" })
  const url = URL.createObjectURL(blob)
  const link = document.createElement("a")
  link.href = url
  link.download = filename
  link.click()
  URL.revokeObjectURL(url)
}

function inPeriod(day: string, start: string, end: string): boolean {
  return day >= start && day <= end
}

function text(value: string): string {
  return csvCell(neutralizeSpreadsheetFormula(value))
}

function value(cell: string): string {
  return csvCell(cell)
}

function row(cells: string[]): string {
  return cells.join(",")
}

function csvCell(value: string): string {
  if (/[",\r\n]/.test(value)) return `"${value.replace(/"/g, '""')}"`
  return value
}

function neutralizeSpreadsheetFormula(value: string): string {
  if (/^[=+@\t\r]/.test(value)) return `'${value}`
  return value
}
