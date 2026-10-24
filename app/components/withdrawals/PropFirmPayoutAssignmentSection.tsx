"use client"

import { useEffect, useMemo, useState } from "react"
import {
  clearPropFirmPayoutAssignment,
  loadPropFirmPayoutAssignments,
  normalizePropFirmAssignmentName,
  savePropFirmPayoutAssignment,
} from "@/lib/propFirmPayoutAssignments"
import { loadPropFirmExpenses } from "@/lib/propFirmExpenses"
import {
  attributedPropFirmName,
  firmNameForPropPayout,
  propFirmNameFromAccount,
  UNASSIGNED_PROP_FIRM,
} from "@/lib/propFirmExpenseTaxExport"
import { supabase } from "@/lib/supabaseClient"
import { READABLE_FIELD_LABEL_CLASS } from "@/lib/readableTextStyles"

const fieldClass =
  "mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"

export default function PropFirmPayoutAssignmentSection({
  userId,
  payoutKey,
  accountId,
  accountName,
}: {
  userId: string
  payoutKey: string
  accountId: string
  accountName?: string | null
}) {
  const [assignments, setAssignments] = useState<Record<string, string>>({})
  const [suggestions, setSuggestions] = useState<string[]>([])
  const [expenses, setExpenses] = useState<Awaited<ReturnType<typeof loadPropFirmExpenses>>["expenses"]>([])
  const [draft, setDraft] = useState("")
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const [names, expenseResult] = await Promise.all([
        loadPropFirmPayoutAssignments(supabase, userId),
        loadPropFirmExpenses(supabase, userId),
      ])
      if (cancelled) return
      setAssignments(names)
      setExpenses(expenseResult.expenses)
      const seen = new Map<string, string>()
      for (const expense of expenseResult.expenses) {
        const label = expense.propFirmName.trim()
        const key = label.toLowerCase()
        if (label && !seen.has(key)) seen.set(key, label)
      }
      for (const label of Object.values(names)) {
        const key = label.toLowerCase()
        if (!seen.has(key)) seen.set(key, label)
      }
      setSuggestions([...seen.values()].sort((a, b) => a.localeCompare(b)))
      setDraft(names[payoutKey] ?? "")
    })()
    return () => {
      cancelled = true
    }
  }, [payoutKey, userId])

  const currentFirm = useMemo(() => {
    return firmNameForPropPayout({
      accountId,
      expenses,
      assignedFirmName: assignments[payoutKey],
      accountName,
    })
  }, [accountId, accountName, assignments, expenses, payoutKey])

  const explicitName = assignments[payoutKey] ?? null

  async function save() {
    setBusy(true)
    setError(null)
    setSaved(false)
    const message = await savePropFirmPayoutAssignment(supabase, userId, payoutKey, draft)
    setBusy(false)
    if (message) {
      setError(message)
      return
    }
    const name = normalizePropFirmAssignmentName(draft)
    if (name) setAssignments((current) => ({ ...current, [payoutKey]: name }))
    setSaved(true)
  }

  async function clear() {
    setBusy(true)
    setError(null)
    setSaved(false)
    const message = await clearPropFirmPayoutAssignment(supabase, userId, payoutKey)
    setBusy(false)
    if (message) {
      setError(message)
      return
    }
    setAssignments((current) => {
      const next = { ...current }
      delete next[payoutKey]
      return next
    })
    setDraft("")
  }

  return (
    <section className="rounded-xl border border-white/10 bg-white/5 p-5">
      <h2 className="text-sm font-semibold text-white">Prop firm</h2>
      <p className="mt-2 text-sm text-gray-300">
        {currentFirm ?? UNASSIGNED_PROP_FIRM}
        {explicitName
          ? ""
          : attributedPropFirmName(accountId, expenses)
            ? " · from the linked expense"
            : propFirmNameFromAccount(accountName)
              ? " · from the account name"
              : ""}
      </p>
      <p className="mt-1 text-xs text-gray-400">
        Assigning a firm updates the expense tracker for this payout. The payout amount and account balance stay the same.
      </p>
      <label className="mt-3 block">
        <span className={READABLE_FIELD_LABEL_CLASS}>Assign to a prop firm</span>
        <input
          value={draft}
          onChange={(event) => {
            setDraft(event.target.value)
            setSaved(false)
          }}
          list="prop-firm-assignment-names"
          placeholder="Apex, Topstep"
          className={fieldClass}
          aria-label="Prop firm name"
        />
        <datalist id="prop-firm-assignment-names">
          {suggestions.map((name) => (
            <option key={name} value={name} />
          ))}
        </datalist>
      </label>
      {error ? <p className="mt-2 text-sm text-red-300">{error}</p> : null}
      {saved ? <p className="mt-2 text-sm text-emerald-200">Firm saved for this payout.</p> : null}
      <div className="mt-3 flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => void save()}
          disabled={busy}
          className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600 disabled:opacity-50"
        >
          {busy ? "Saving…" : "Assign to prop firm"}
        </button>
        {explicitName ? (
          <button
            type="button"
            onClick={() => void clear()}
            disabled={busy}
            className="rounded-lg border border-white/15 px-4 py-2 text-sm text-gray-200 disabled:opacity-50"
          >
            Remove assignment
          </button>
        ) : null}
      </div>
    </section>
  )
}
