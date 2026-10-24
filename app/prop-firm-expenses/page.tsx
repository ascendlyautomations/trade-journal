"use client"

import "../utilityDesktopTheme.css"
import Link from "next/link"
import { useRouter } from "next/navigation"
import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import PropFirmExpenseEditorModal from "@/app/components/propFirmExpenses/PropFirmExpenseEditorModal"
import PropFirmExpenseTaxExportModal from "@/app/components/propFirmExpenses/PropFirmExpenseTaxExportModal"
import TrackerIncomeEditorModal from "@/app/components/propFirmExpenses/TrackerIncomeEditorModal"
import EmptyState from "@/app/components/ui/EmptyState"
import {
  EXPENSE_TRACKER_KINDS,
  PROP_FIRM_EXPENSE_TYPES,
  createPropFirmExpense,
  decimalToCents,
  deletePropFirmExpense,
  expenseCategoryLabel,
  expenseTrackerKindLabel,
  expandPropFirmExpenses,
  filterPropFirmExpenses,
  formatCents,
  loadExpenseCategories,
  loadPropFirmExpenses,
  saveExpenseCategory,
  summarizeExpenseTracker,
  updatePropFirmExpense,
  type PropFirmExpenseDraft,
  type PropFirmExpenseRecord,
} from "@/lib/propFirmExpenses"
import {
  DEFAULT_TAX_RESERVE_PERCENT,
  TAX_RESERVE_PRESETS,
  UNASSIGNED_FIRM_KEY,
  buildPropFirmYearOverview,
  formatTaxReservePercent,
  isTaxReservePreset,
  loadTaxReservePercent,
  parseTaxReservePercent,
  saveTaxReservePercent,
} from "@/lib/propFirmExpenseOverview"
import {
  loadPropFirmPayoutAssignments,
  peekPropFirmPayoutAssignments,
  subscribePropFirmPayoutAssignments,
} from "@/lib/propFirmPayoutAssignments"
import {
  payoutCalendarDay,
  propFirmKey,
  taxYearPeriod,
} from "@/lib/propFirmExpenseTaxExport"
import { expenseRecurrenceLabel } from "@/lib/expenseRecurrence"
import { filterPropFirmTrackerPayouts } from "@/lib/payoutHistory"
import { supabase } from "@/lib/supabaseClient"
import { getLocalTodayDateInputValue } from "@/lib/tradeDateValidation"
import { useScrollPageTopOnMount } from "@/lib/useScrollPageTopOnMount"
import { useUserProfile } from "@/lib/useUserProfile"
import { useWithdrawalsHistory } from "@/lib/useWithdrawalsHistory"
import {
  createTrackerIncome,
  deleteTrackerIncome,
  expandTrackerIncome,
  incomeHistorySubtitle,
  loadTrackerIncome,
  summarizeMoneyTracker,
  trackerIncomeFromWithdrawals,
  updateTrackerIncome,
  type TrackerIncomeDraft,
  type TrackerIncomeRecord,
} from "@/lib/trackerIncome"

export default function PropFirmExpensesPage() {
  useScrollPageTopOnMount()
  const router = useRouter()
  const { user, loading: profileLoading } = useUserProfile()
  const payouts = useWithdrawalsHistory(user?.id)
  const [expenses, setExpenses] = useState<PropFirmExpenseRecord[]>([])
  const [income, setIncome] = useState<TrackerIncomeRecord[]>([])
  const [incomeEditorOpen, setIncomeEditorOpen] = useState(false)
  const [editingIncome, setEditingIncome] = useState<TrackerIncomeRecord | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [firm, setFirm] = useState("all")
  const [kind, setKind] = useState("all")
  const [project, setProject] = useState("all")
  const [category, setCategory] = useState("all")
  const [categories, setCategories] = useState<string[]>([])
  const [from, setFrom] = useState("")
  const [to, setTo] = useState("")
  const [editorOpen, setEditorOpen] = useState(false)
  const [exportOpen, setExportOpen] = useState(false)
  const [editing, setEditing] = useState<PropFirmExpenseRecord | null>(null)
  const [busy, setBusy] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const currentYear = Number(getLocalTodayDateInputValue().slice(0, 4))
  const [year, setYear] = useState(currentYear)
  const [reservePercent, setReservePercent] = useState(DEFAULT_TAX_RESERVE_PERCENT)
  const [reserveMode, setReserveMode] = useState<"preset" | "custom">("preset")
  const [customPercent, setCustomPercent] = useState("")
  const [reserveError, setReserveError] = useState<string | null>(null)
  const [assignments, setAssignments] = useState<Record<string, string>>({})
  const reserveSaveTimer = useRef<number | null>(null)

  const reload = useCallback(async (force = false) => {
    if (!user?.id) {
      setExpenses([])
      setLoading(false)
      return
    }
    setLoading(true)
    const [result, percent, payoutFirms, savedCategories, incomeResult] = await Promise.all([
      loadPropFirmExpenses(supabase, user.id, { force }),
      loadTaxReservePercent(supabase, user.id, { force }),
      loadPropFirmPayoutAssignments(supabase, user.id, { force }),
      loadExpenseCategories(supabase, user.id),
      loadTrackerIncome(supabase, user.id, { force }),
    ])
    setExpenses(result.expenses)
    setIncome(incomeResult.income)
    setCategories(savedCategories)
    setAssignments(payoutFirms)
    setError(result.error ?? incomeResult.error)
    setReservePercent(percent)
    if (isTaxReservePreset(percent)) {
      setReserveMode("preset")
    } else {
      setReserveMode("custom")
      setCustomPercent(formatTaxReservePercent(percent))
    }
    setLoading(false)
  }, [user?.id])

  useEffect(() => {
    void reload(false)
  }, [reload])

  useEffect(() => {
    if (!profileLoading && !user) {
      router.replace("/login")
    }
  }, [profileLoading, user, router])

  useEffect(() => {
    return subscribePropFirmPayoutAssignments(() => {
      if (!user?.id) return
      setAssignments(peekPropFirmPayoutAssignments(user.id))
    })
  }, [user?.id])

  const overviewPayouts = useMemo(() => {
    return filterPropFirmTrackerPayouts(payouts.items, payouts.accountsById, assignments).flatMap((item) => {
      const payoutDate = payoutCalendarDay(item.payoutDate, item.dateMs)
      if (!payoutDate) return []
      return [{
        payoutDate,
        accountId: item.accountId,
        amountCents: decimalToCents(item.amount),
        assignedFirmName: assignments[item.id] ?? null,
        accountName: payouts.accountsById[item.accountId]?.name ?? null,
      }]
    })
  }, [assignments, payouts.accountsById, payouts.items])

  const expandedExpenses = useMemo(() => expandPropFirmExpenses(expenses), [expenses])
  const recordedIncome = useMemo(() => expandTrackerIncome(income), [income])
  const withdrawalIncome = useMemo(
    () => trackerIncomeFromWithdrawals(payouts.items, payouts.accountsById),
    [payouts.accountsById, payouts.items]
  )

  const overview = useMemo(
    () =>
      buildPropFirmYearOverview({
        year,
        expenses: expandedExpenses,
        payouts: overviewPayouts,
        reservePercent,
      }),
    [year, expandedExpenses, overviewPayouts, reservePercent]
  )

  const years = useMemo(() => {
    const found = new Set<number>([currentYear, year])
    for (const expense of expandedExpenses) {
      const value = Number(expense.datePaid.slice(0, 4))
      if (value >= 2000 && value <= 2100) found.add(value)
    }
    for (const row of recordedIncome) {
      const value = Number(row.dateReceived.slice(0, 4))
      if (value >= 2000 && value <= 2100) found.add(value)
    }
    for (const payout of overviewPayouts) {
      const value = Number(payout.payoutDate.slice(0, 4))
      if (value >= 2000 && value <= 2100) found.add(value)
    }
    return [...found].sort((a, b) => b - a)
  }, [currentYear, expandedExpenses, overviewPayouts, recordedIncome, year])

  const period = taxYearPeriod(year) ?? { start: `${year}-01-01`, end: `${year}-12-31` }

  const firms = useMemo(() => {
    const names = new Map<string, string>()
    for (const expense of expandedExpenses) {
      const key = propFirmKey(expense.propFirmName)
      if (!names.has(key)) names.set(key, expense.propFirmName.trim())
    }
    return [...names.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [expandedExpenses])

  const listFrom = from && from > period.start ? from : period.start
  const listTo = to && to < period.end ? to : period.end

  const filtered = useMemo(
    () =>
      filterPropFirmExpenses(expandedExpenses, {
        firm,
        category,
        from: listFrom,
        to: listTo,
        kind,
        project,
      }),
    [expandedExpenses, firm, category, listFrom, listTo, kind, project]
  )

  const money = useMemo(() => {
    const start = period.start
    const end = period.end
    const yearExpenses = expandedExpenses.filter(
      (expense) => expense.datePaid >= start && expense.datePaid <= end
    )
    const yearIncome = [...withdrawalIncome, ...recordedIncome].filter(
      (row) => row.dateReceived >= start && row.dateReceived <= end
    )
    return summarizeMoneyTracker({
      expensesCents: yearExpenses.map((expense) => expense.totalCostCents),
      income: yearIncome,
    })
  }, [expandedExpenses, period.end, period.start, recordedIncome, withdrawalIncome])

  const incomeHistory = useMemo(() => {
    return [...withdrawalIncome, ...recordedIncome]
      .filter((row) => row.dateReceived >= listFrom && row.dateReceived <= listTo)
      .sort((a, b) => b.dateReceived.localeCompare(a.dateReceived) || b.id.localeCompare(a.id))
  }, [listFrom, listTo, recordedIncome, withdrawalIncome])

  const spending = useMemo(() => summarizeExpenseTracker(filtered), [filtered])
  const projects = useMemo(() => {
    const names = new Map<string, string>()
    for (const expense of expenses) {
      const label = (expense.projectLabel ?? "").trim()
      if (!label) continue
      const key = label.toLowerCase()
      if (!names.has(key)) names.set(key, label)
    }
    return [...names.entries()].sort((a, b) => a[1].localeCompare(b[1]))
  }, [expenses])

  const accounts = useMemo(
    () =>
      payouts.accounts.map((account) => ({
        id: account.id,
        name: account.name?.trim() || "Account",
      })),
    [payouts.accounts]
  )

  const accountNames = useMemo(() => {
    const map = new Map<string, string>()
    for (const account of accounts) map.set(account.id, account.name)
    return map
  }, [accounts])

  if (!profileLoading && !user) {
    return null
  }

  async function saveDraft(draft: PropFirmExpenseDraft) {
    if (!user?.id || busy) return
    setBusy(true)
    setFormError(null)
    const result = editing
      ? await updatePropFirmExpense(supabase, user.id, editing.id, draft, editing.source)
      : await createPropFirmExpense(supabase, user.id, draft)
    setBusy(false)
    if (result.error || !result.expense) {
      setFormError(result.error ?? "Couldn't save that expense.")
      return
    }
    if (draft.trackerKind !== "prop_firm" && draft.customCategory.trim()) {
      await saveExpenseCategory(supabase, user.id, draft.customCategory)
    }
    setEditorOpen(false)
    setEditing(null)
    await reload(true)
  }

  async function removeExpense() {
    if (!user?.id || !editing || busy) return
    setBusy(true)
    const result = await deletePropFirmExpense(supabase, user.id, editing.id)
    setBusy(false)
    if (result.error) {
      setFormError(result.error)
      return
    }
    setEditorOpen(false)
    setEditing(null)
    await reload(true)
  }

  async function saveIncome(draft: TrackerIncomeDraft) {
    if (!user?.id || busy) return
    setBusy(true)
    setFormError(null)
    const result = editingIncome
      ? await updateTrackerIncome(supabase, user.id, editingIncome.seriesId, draft)
      : await createTrackerIncome(supabase, user.id, draft)
    setBusy(false)
    if (result.error || !result.income) {
      setFormError(result.error ?? "Couldn't save that income.")
      return
    }
    setIncomeEditorOpen(false)
    setEditingIncome(null)
    await reload(true)
  }

  async function removeIncome() {
    if (!user?.id || !editingIncome || busy) return
    setBusy(true)
    const result = await deleteTrackerIncome(supabase, user.id, editingIncome.seriesId)
    setBusy(false)
    if (result.error) {
      setFormError(result.error)
      return
    }
    setIncomeEditorOpen(false)
    setEditingIncome(null)
    await reload(true)
  }

  function persistReserve(percent: number) {
    if (!user?.id) return
    if (reserveSaveTimer.current) window.clearTimeout(reserveSaveTimer.current)
    reserveSaveTimer.current = window.setTimeout(() => {
      const userId = user.id
      void saveTaxReservePercent(supabase, userId, percent).then(setReserveError)
    }, 250)
  }

  const chartMax = Math.max(
    ...overview.months.flatMap((month) => [month.expenseCents, month.payoutCents]),
    1
  )
  const mostProfitable = overview.firms.find((firmRow) => firmRow.key === overview.mostProfitableFirmKey)

  return (
    <div className="tt-phase4-dark min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
      <div className="mx-auto max-w-6xl px-4 py-6 sm:px-6 lg:py-8">
        <div className="mb-5 flex flex-wrap items-end justify-between gap-x-6 gap-y-3">
          <div className="min-w-0">
            <Link href="/settings" className="text-sm text-blue-300 hover:text-blue-200">
              ← Settings
            </Link>
            <h1 className="mt-2 text-2xl font-bold text-blue-300 sm:text-3xl">
              Expense Tracker
            </h1>
            <p className="mt-1 max-w-xl text-sm text-gray-400">
              {year} income and expenses. Withdrawals you already recorded are included.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-2 text-xs text-gray-400">
              Tax year
              <select
                value={year}
                onChange={(event) => setYear(Number(event.target.value))}
                className="rounded-lg border border-white/15 bg-white px-2 py-1.5 text-sm text-gray-900"
                aria-label="Tax year"
              >
                {years.map((option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ))}
              </select>
            </label>
            <button
              type="button"
              onClick={() => {
                setEditingIncome(null)
                setFormError(null)
                setIncomeEditorOpen(true)
              }}
              className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white hover:bg-emerald-500"
              data-tt-tour-target="expenseTrackerIncome"
            >
              Add income
            </button>
            <button
              type="button"
              onClick={() => {
                setEditing(null)
                setFormError(null)
                setEditorOpen(true)
              }}
              className="rounded-xl bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600"
              data-tt-tour-target="expenseTrackerAdd"
            >
              Add expense
            </button>
          </div>
        </div>

        {error ? (
          <div className="mb-6 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-100">
            {error}
            <button type="button" onClick={() => void reload(true)} className="ml-2 underline">
              Retry
            </button>
          </div>
        ) : null}

        <section className="mb-8">
          <div className="grid gap-3 sm:grid-cols-3">
            <Metric label="Income" value={formatCents(money.incomeCents)} tone="positive" />
            <Metric label="Expenses" value={formatCents(money.expenseCents)} />
            <Metric
              label="Net"
              value={formatCents(money.netCents)}
              tone={money.netCents > 0 ? "positive" : money.netCents < 0 ? "negative" : "neutral"}
            />
          </div>
          <p className="mt-3 text-sm text-gray-400">
            Withdrawals {formatCents(money.withdrawalCents)}
            {" · "}
            Business income {formatCents(money.businessCents)}
          </p>
        </section>

        <section className="mb-8">
          <div className="grid items-start gap-6 lg:grid-cols-2">
            <div>
              <div className="mb-3 flex items-center justify-between gap-3">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
                  Income
                </h2>
                <Link
                  href="/withdrawals"
                  className="rounded-lg bg-blue-500 px-3 py-1.5 text-xs font-semibold text-white hover:bg-blue-600"
                >
                  Withdrawals
                </Link>
              </div>
              {incomeHistory.length === 0 ? (
                <EmptyState
                  title="No income yet"
                  description="Withdrawals you already recorded show up here. Add business income for money a project receives."
                />
              ) : (
                <ul className="max-h-[32rem] divide-y divide-white/10 overflow-y-auto rounded-xl border border-emerald-400/20 bg-white/5">
                  {incomeHistory.map((row) => (
                    <li key={row.id}>
                      <button
                        type="button"
                        onClick={() => {
                          if (row.source === "withdrawal" && row.href) {
                            router.push(row.href)
                            return
                          }
                          const source = income.find((item) => item.id === row.seriesId) ?? row
                          setEditingIncome(source)
                          setFormError(null)
                          setIncomeEditorOpen(true)
                        }}
                        className="flex w-full items-start justify-between gap-3 px-4 py-3 text-left hover:bg-white/5"
                      >
                        <span>
                          <span className="block font-medium text-white">{row.name}</span>
                          <span className="mt-0.5 block text-xs text-gray-400">{incomeHistorySubtitle(row)}</span>
                        </span>
                        <span className="shrink-0 tabular-nums text-emerald-300">
                          {formatCents(row.amountCents)}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            <div>
              <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
                <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
                  Expenses
                </h2>
              </div>
              <div className="mb-3 flex flex-wrap gap-2">
                <select
                  value={kind}
                  onChange={(event) => setKind(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="Filter by expense type"
                >
                  <option value="all">All types</option>
                  {EXPENSE_TRACKER_KINDS.map((item) => (
                    <option key={item.value} value={item.value}>
                      {item.label}
                    </option>
                  ))}
                </select>
                <select
                  value={project}
                  onChange={(event) => setProject(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="Filter by business or project"
                >
                  <option value="all">All projects</option>
                  {projects.map(([key, label]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
                <select
                  value={firm}
                  onChange={(event) => setFirm(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="Filter by name"
                >
                  <option value="all">All names</option>
                  {firms.map(([key, label]) => (
                    <option key={key} value={key}>
                      {label}
                    </option>
                  ))}
                </select>
                <select
                  value={category}
                  onChange={(event) => setCategory(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="Filter by category"
                >
                  <option value="all">All categories</option>
                  {PROP_FIRM_EXPENSE_TYPES.map((type) => (
                    <option key={type.value} value={type.value}>
                      Prop firm · {type.label}
                    </option>
                  ))}
                  {categories.map((name) => (
                    <option key={name} value={`custom:${name.toLowerCase()}`}>
                      {name}
                    </option>
                  ))}
                </select>
                <input
                  type="date"
                  value={from}
                  onChange={(event) => setFrom(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="From date"
                />
                <input
                  type="date"
                  value={to}
                  onChange={(event) => setTo(event.target.value)}
                  className="rounded-lg border border-white/15 bg-black/30 px-2 py-1.5 text-sm"
                  aria-label="To date"
                />
              </div>
              {loading && expenses.length === 0 ? (
                <p className="text-sm text-gray-400">Loading expenses…</p>
              ) : filtered.length === 0 ? (
                <EmptyState
                  title={expenses.length === 0 ? "No expenses yet" : "No expenses in this view"}
                  description="Add a prop firm fee, business cost, or trading tool."
                />
              ) : (
                <ul className="max-h-[32rem] divide-y divide-white/10 overflow-y-auto rounded-xl border border-white/10 bg-white/5">
                  {filtered.map((expense) => (
                    <li key={expense.id}>
                      <button
                        type="button"
                        onClick={() => {
                          const source = expenses.find((item) => item.id === expense.seriesId) ?? expense
                          setEditing(source)
                          setFormError(null)
                          setEditorOpen(true)
                        }}
                        className="flex w-full items-start justify-between gap-3 px-4 py-3 text-left hover:bg-white/5"
                      >
                        <span>
                          <span className="block font-medium text-white">{expense.propFirmName}</span>
                          <span className="mt-0.5 block text-xs text-gray-400">
                            {expenseTrackerKindLabel(expense.trackerKind)} · {expenseCategoryLabel(expense)}
                            {expenseRecurrenceLabel(expense.recurrence)
                              ? ` · ${expenseRecurrenceLabel(expense.recurrence)}`
                              : ""}
                            {" · "}
                            {expense.datePaid}
                            {expense.quantity > 1 ? ` · ${expense.quantity} accounts` : ""}
                            {expense.paymentLabel ? ` · ${expense.paymentLabel}` : ""}
                            {expense.accountId
                              ? ` · ${accountNames.get(expense.accountId) ?? "Linked account"}`
                              : ""}
                          </span>
                        </span>
                        <span className="shrink-0 tabular-nums text-white">
                          {formatCents(expense.totalCostCents)}
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        </section>

        <section className="mb-8">
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
            Breakdown
          </h2>
          <div className="grid gap-3 lg:grid-cols-3">
            <Breakdown title="Type" rows={spending.byKind} empty="No spending yet." />
            <Breakdown title="Category" rows={spending.byCategory} empty="No categories yet." />
            <Breakdown title="Business or project" rows={spending.byProject} empty="No projects yet." />
          </div>
        </section>

        <section id="prop-firm" className="scroll-mt-24" data-tt-tour-target="expenseTrackerAnalytics">
          <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
                Prop firm
              </h2>
              <p className="mt-1 text-sm text-gray-400">
                Payouts {formatCents(overview.payoutCents)}
                {" · "}
                Expenses {formatCents(overview.expenseCents)}
                {" · "}
                Net {formatCents(overview.netCents)}
              </p>
            </div>
            <button
              type="button"
              onClick={() => setExportOpen(true)}
              className="rounded-xl border border-white/15 px-4 py-2 text-sm font-semibold text-white hover:bg-white/10"
              data-tt-tour-target="expenseTrackerExport"
            >
              Download CSV
            </button>
          </div>
          <div className="mb-4 grid items-start gap-3 lg:grid-cols-2">
            <div className="rounded-xl border border-white/10 bg-white/5 px-4 py-3">
              <p className="text-xs text-gray-400">Estimated Tax Reserve</p>
              <p className="mt-1 text-lg font-semibold tabular-nums text-white">
                {formatCents(overview.reserveCents)}
              </p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {TAX_RESERVE_PRESETS.map((preset) => (
                  <button
                    key={preset}
                    type="button"
                    onClick={() => {
                      setReserveMode("preset")
                      setReservePercent(preset)
                      setReserveError(null)
                      persistReserve(preset)
                    }}
                    className={`rounded-full border px-2.5 py-0.5 text-xs ${
                      reserveMode === "preset" && reservePercent === preset
                        ? "border-transparent bg-blue-500 text-white"
                        : "tt-expense-chip border-white/15 bg-white text-gray-800"
                    }`}
                  >
                    {preset}%
                  </button>
                ))}
                <button
                  type="button"
                  onClick={() => setReserveMode("custom")}
                  className={`rounded-full border px-2.5 py-0.5 text-xs ${
                    reserveMode === "custom"
                      ? "border-transparent bg-blue-500 text-white"
                      : "tt-expense-chip border-white/15 bg-white text-gray-800"
                  }`}
                >
                  Custom
                </button>
              </div>
              {reserveMode === "custom" ? (
                <label className="mt-2 block text-xs text-gray-400">
                  Custom percentage
                  <input
                    inputMode="decimal"
                    value={customPercent}
                    onChange={(event) => {
                      const next = event.target.value
                      setCustomPercent(next)
                      const parsed = parseTaxReservePercent(next)
                      if (parsed == null) return
                      setReservePercent(parsed)
                      setReserveError(null)
                      persistReserve(parsed)
                    }}
                    placeholder="22.5"
                    className="mt-1 w-28 rounded-lg border border-white/15 bg-white px-3 py-1.5 text-sm text-gray-900"
                    aria-label="Custom tax reserve percentage"
                  />
                </label>
              ) : null}
              {reserveError ? <p className="mt-2 text-sm text-red-300">{reserveError}</p> : null}
            </div>
            <Metric
              label="Potential Tax-Deductible Expenses"
              value={formatCents(overview.deductibleEstimateCents)}
              detail="Unverified estimate"
            />
          </div>
          <div className="grid items-start gap-6 lg:grid-cols-2">
            <section>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
                Firms
              </h3>
              {mostProfitable ? (
                <p className="mb-3 text-sm text-emerald-200">
                  Most profitable: {mostProfitable.label}
                </p>
              ) : (
                <p className="mb-3 text-sm text-gray-400">No firm is attributed for {year} yet.</p>
              )}
              {overview.firms.length === 0 ? (
                <p className="text-sm text-gray-400">No spending or payouts in {year}.</p>
              ) : (
                <ul className="space-y-3">
                  {overview.firms.map((firmRow) => (
                    <li
                      key={firmRow.key}
                      className={`rounded-xl border px-4 py-3 ${
                        firmRow.key === overview.mostProfitableFirmKey
                          ? "border-emerald-300/50 bg-emerald-500/10"
                          : "border-white/10 bg-white/5"
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-medium text-white">{firmRow.label}</p>
                        <p
                          className={`shrink-0 tabular-nums ${
                            firmRow.netCents > 0
                              ? "text-emerald-300"
                              : firmRow.netCents < 0
                                ? "text-red-300"
                                : "text-white"
                          }`}
                        >
                          {formatCents(firmRow.netCents)} net
                        </p>
                      </div>
                      <p className="mt-1 text-xs text-gray-400">
                        Spent {formatCents(firmRow.spentCents)} · Payouts {formatCents(firmRow.payoutCents)}
                      </p>
                      {firmRow.key === UNASSIGNED_FIRM_KEY ? (
                        <p className="mt-1 text-xs text-gray-400">
                          These payouts are not tied to one recorded prop firm.
                        </p>
                      ) : null}
                    </li>
                  ))}
                </ul>
              )}
            </section>
            <section>
              <h3 className="mb-3 text-sm font-semibold uppercase tracking-wide text-gray-400">
                Payouts vs. expenses
              </h3>
              <div className="rounded-xl border border-white/10 bg-white/5 p-4">
                <p className="mb-3 text-xs text-gray-400">
                  <span className="text-emerald-300">Payouts</span>
                  {" · "}
                  <span className="text-blue-300">Expenses</span>
                </p>
                <div className="flex h-36 items-end gap-1">
                  {overview.months.map((month) => (
                    <div key={month.monthKey} className="flex min-w-0 flex-1 flex-col items-center gap-1">
                      <div className="flex h-28 items-end gap-0.5">
                        <div
                          className="w-1.5 rounded-t bg-emerald-400/80 sm:w-2"
                          style={{ height: barHeight(month.payoutCents, chartMax) }}
                          title={`${month.label} payouts: ${formatCents(month.payoutCents)}`}
                        />
                        <div
                          className="w-1.5 rounded-t bg-blue-400/80 sm:w-2"
                          style={{ height: barHeight(month.expenseCents, chartMax) }}
                          title={`${month.label} expenses: ${formatCents(month.expenseCents)}`}
                        />
                      </div>
                      <span className="text-[10px] text-gray-400">{month.label}</span>
                    </div>
                  ))}
                </div>
              </div>
            </section>
          </div>
        </section>
      </div>

      <PropFirmExpenseEditorModal
        open={editorOpen}
        expense={editing}
        accounts={accounts}
        categories={categories}
        busy={busy}
        error={formError}
        onClose={() => {
          if (busy) return
          setEditorOpen(false)
          setEditing(null)
        }}
        onSave={(draft) => void saveDraft(draft)}
        onDelete={editing ? () => void removeExpense() : undefined}
      />
      <TrackerIncomeEditorModal
        open={incomeEditorOpen}
        income={editingIncome}
        busy={busy}
        error={formError}
        onClose={() => {
          if (busy) return
          setIncomeEditorOpen(false)
          setEditingIncome(null)
        }}
        onSave={(draft) => void saveIncome(draft)}
        onDelete={editingIncome ? () => void removeIncome() : undefined}
      />
      <PropFirmExpenseTaxExportModal
        open={exportOpen}
        onClose={() => setExportOpen(false)}
        expenses={expandedExpenses}
        payoutItems={payouts.items}
        accountsById={payouts.accountsById}
        initialYear={year}
        reservePercent={reservePercent}
        assignments={assignments}
      />
    </div>
  )
}

function barHeight(cents: number, maximum: number): string {
  if (cents <= 0) return "0px"
  return `${Math.max(4, Math.round((cents / maximum) * 112))}px`
}

function Metric({
  label,
  value,
  detail,
  tone = "neutral",
}: {
  label: string
  value: string
  detail?: string
  tone?: "neutral" | "positive" | "negative"
}) {
  const color =
    tone === "positive" ? "text-emerald-300" : tone === "negative" ? "text-red-300" : "text-white"
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 px-4 py-3">
      <p className="text-xs text-gray-400">{label}</p>
      <p className={`mt-1 text-lg font-semibold tabular-nums ${color}`}>{value}</p>
      {detail ? <p className="mt-1 text-[11px] text-gray-500">{detail}</p> : null}
    </div>
  )
}

function Breakdown({
  title,
  rows,
  empty,
}: {
  title: string
  rows: Array<{ key: string; label: string; totalCents: number }>
  empty: string
}) {
  const max = Math.max(...rows.map((row) => row.totalCents), 1)
  return (
    <section className="rounded-xl border border-white/10 bg-white/5 p-4">
      <h2 className="text-sm font-semibold uppercase tracking-wide text-gray-400">{title}</h2>
      {rows.length === 0 ? (
        <p className="mt-3 text-sm text-gray-400">{empty}</p>
      ) : (
        <ul className="mt-3 space-y-3">
          {rows.map((row) => (
            <li key={row.key}>
              <div className="mb-1 flex items-center justify-between gap-3 text-sm">
                <span className="truncate text-white">{row.label}</span>
                <span className="shrink-0 tabular-nums text-gray-200">
                  {formatCents(row.totalCents)}
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-white/10">
                <div
                  className="h-full rounded-full bg-blue-400"
                  style={{ width: `${(row.totalCents / max) * 100}%` }}
                />
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
