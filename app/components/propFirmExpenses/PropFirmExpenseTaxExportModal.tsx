"use client"

import { useEffect, useMemo, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  buildExpenseTrackerCsv,
  downloadPropFirmTaxCsv,
  payoutCalendarDay,
  firmNameForPropPayout,
  taxCustomPeriod,
  taxYearPeriod,
  type TaxExportPayout,
} from "@/lib/propFirmExpenseTaxExport"
import {
  EXPENSE_TRACKER_KINDS,
  decimalToCents,
  type ExpenseTrackerKind,
  type PropFirmExpenseRecord,
} from "@/lib/propFirmExpenses"
import { filterPropFirmTrackerPayouts, type PayoutHistoryAccount, type PayoutHistoryItem } from "@/lib/payoutHistory"
import { getLocalTodayDateInputValue } from "@/lib/tradeDateValidation"
import { READABLE_FIELD_LABEL_CLASS } from "@/lib/readableTextStyles"

const fieldClass =
  "mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"

export default function PropFirmExpenseTaxExportModal({
  open,
  onClose,
  expenses,
  payoutItems,
  accountsById,
  initialYear,
  reservePercent,
  assignments,
}: {
  open: boolean
  onClose: () => void
  expenses: PropFirmExpenseRecord[]
  payoutItems: PayoutHistoryItem[]
  accountsById: Record<string, PayoutHistoryAccount | undefined>
  initialYear: number
  reservePercent: number
  assignments: Record<string, string>
}) {
  const today = getLocalTodayDateInputValue()
  const currentYear = Number(today.slice(0, 4))
  const taxPayouts = useMemo<TaxExportPayout[]>(() => {
    return filterPropFirmTrackerPayouts(payoutItems, accountsById, assignments).flatMap((item) => {
      const payoutDate = payoutCalendarDay(item.payoutDate, item.dateMs)
      if (!payoutDate) return []
      return [{
        payoutDate,
        propFirmName:
          firmNameForPropPayout({
            accountId: item.accountId,
            expenses,
            assignedFirmName: assignments[item.id],
            accountName: accountsById[item.accountId]?.name,
          }) ?? "Unassigned",
        amountCents: decimalToCents(item.amount),
      }]
    })
  }, [accountsById, assignments, expenses, payoutItems])
  const years = useMemo(() => {
    const found = new Set<number>([currentYear, initialYear])
    for (const expense of expenses) {
      const year = Number(expense.datePaid.slice(0, 4))
      if (year >= 2000 && year <= 2100) found.add(year)
    }
    for (const item of taxPayouts) {
      const year = Number(item.payoutDate.slice(0, 4))
      if (year >= 2000 && year <= 2100) found.add(year)
    }
    return [...found].sort((a, b) => b - a)
  }, [currentYear, expenses, initialYear, taxPayouts])

  const [mode, setMode] = useState<"year" | "custom">("year")
  const [year, setYear] = useState(initialYear)
  const [from, setFrom] = useState(`${initialYear}-01-01`)
  const [to, setTo] = useState(today)

  useEffect(() => {
    if (!open) return
    setYear(initialYear)
  }, [open, initialYear])
  const [error, setError] = useState<string | null>(null)
  const [kinds, setKinds] = useState<ExpenseTrackerKind[]>(["prop_firm"])
  const [project, setProject] = useState("all")
  const projects = useMemo(() => {
    const names = new Map<string, string>()
    for (const expense of expenses) {
      const label = (expense.projectLabel ?? "").trim()
      if (!label) continue
      const key = label.toLowerCase()
      if (!names.has(key)) names.set(key, label)
    }
    return [...names.entries()]
  }, [expenses])

  function exportCsv() {
    const period = mode === "year" ? taxYearPeriod(year) : taxCustomPeriod(from, to)
    if (!period) {
      setError("Choose a tax year, or a start date on or before the end date.")
      return
    }
    if (kinds.length === 0) {
      setError("Choose at least one expense type.")
      return
    }
    const file = buildExpenseTrackerCsv({
      periodStart: period.start,
      periodEnd: period.end,
      expenses,
      payouts: taxPayouts,
      kinds,
      projectKey: project,
      reservePercent,
    })
    downloadPropFirmTaxCsv(file.filename, file.csv)
    setError(null)
    onClose()
  }

  return (
    <Modal open={open} onClose={onClose} title="Export Tax CSV">
      <div className="space-y-4">
        <p className="text-sm text-gray-300">
          Choose the expense types and, if you want, one business or project.
          A prop-firm-only file keeps the existing tax summary. Files that include
          other expense types list recorded totals and do not assume a deduction.
        </p>
        <fieldset className="space-y-2">
          <legend className={READABLE_FIELD_LABEL_CLASS}>Expense types</legend>
          {EXPENSE_TRACKER_KINDS.map((item) => (
            <label key={item.value} className="flex items-center gap-2 text-sm text-gray-200">
              <input
                type="checkbox"
                checked={kinds.includes(item.value)}
                onChange={(event) => {
                  setKinds((current) =>
                    event.target.checked
                      ? [...current, item.value]
                      : current.filter((kind) => kind !== item.value)
                  )
                }}
              />
              {item.label}
            </label>
          ))}
        </fieldset>
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Business or project</span>
          <select value={project} onChange={(event) => setProject(event.target.value)} className={fieldClass}>
            <option value="all">All projects</option>
            {projects.map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Reporting period</span>
          <select
            value={mode}
            onChange={(event) => setMode(event.target.value === "custom" ? "custom" : "year")}
            className={fieldClass}
          >
            <option value="year">Tax year</option>
            <option value="custom">Custom date range</option>
          </select>
        </label>
        {mode === "year" ? (
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Tax year</span>
            <select
              value={year}
              onChange={(event) => setYear(Number(event.target.value))}
              className={fieldClass}
            >
              {years.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </label>
        ) : (
          <div className="grid grid-cols-2 gap-3">
            <label className="block">
              <span className={READABLE_FIELD_LABEL_CLASS}>From</span>
              <NativeDateInput
                value={from}
                onChange={(event) => setFrom(event.currentTarget.value)}
                className="mt-1 w-full"
              />
            </label>
            <label className="block">
              <span className={READABLE_FIELD_LABEL_CLASS}>To</span>
              <NativeDateInput
                value={to}
                onChange={(event) => setTo(event.currentTarget.value)}
                className="mt-1 w-full"
              />
            </label>
          </div>
        )}
        {error ? (
          <p className="text-sm text-red-300" role="alert">
            {error}
          </p>
        ) : null}
        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="rounded-xl border border-white/15 px-4 py-2 text-sm text-gray-200"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={exportCsv}
            className="rounded-xl bg-emerald-500 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-600"
          >
            Download CSV
          </button>
        </div>
      </div>
    </Modal>
  )
}
