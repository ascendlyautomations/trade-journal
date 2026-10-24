"use client"

import { useEffect, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import RecurrenceChoices from "@/app/components/propFirmExpenses/RecurrenceChoices"
import {
  TRACKER_INCOME_KINDS,
  draftFromTrackerIncome,
  emptyTrackerIncomeDraft,
  formatIncomeAmount,
  validateTrackerIncomeDraft,
  type TrackerIncomeDraft,
  type TrackerIncomeRecord,
} from "@/lib/trackerIncome"
import { parseMoneyToCents, sanitizeMoneyInput } from "@/lib/propFirmExpenses"
import { READABLE_FIELD_LABEL_CLASS, READABLE_PRIMARY_CLASS } from "@/lib/readableTextStyles"

const fieldClass =
  "mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"

export default function TrackerIncomeEditorModal({
  open,
  income,
  busy = false,
  error = null,
  onClose,
  onSave,
  onDelete,
}: {
  open: boolean
  income: TrackerIncomeRecord | null
  busy?: boolean
  error?: string | null
  onClose: () => void
  onSave: (draft: TrackerIncomeDraft) => void
  onDelete?: () => void
}) {
  const [draft, setDraft] = useState<TrackerIncomeDraft>(emptyTrackerIncomeDraft())
  const [confirmDelete, setConfirmDelete] = useState(false)
  const business = draft.incomeKind === "business"
  const validationError = validateTrackerIncomeDraft(draft)
  const amount = parseMoneyToCents(draft.amountDigits)

  useEffect(() => {
    if (!open) return
    setDraft(income ? draftFromTrackerIncome(income) : emptyTrackerIncomeDraft())
    setConfirmDelete(false)
  }, [open, income])

  return (
    <Modal open={open} onClose={onClose} title={income ? "Edit Income" : "Add Income"}>
      <div className="space-y-4">
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Income Type</span>
          <select
            value={draft.incomeKind}
            onChange={(event) =>
              setDraft((current) => ({
                ...current,
                incomeKind: event.target.value as TrackerIncomeDraft["incomeKind"],
                projectLabel: event.target.value === "business" ? current.projectLabel : "",
              }))
            }
            className={fieldClass}
          >
            {TRACKER_INCOME_KINDS.map((kind) => (
              <option key={kind.value} value={kind.value}>
                {kind.label}
              </option>
            ))}
          </select>
          <p className="mt-1 text-xs text-gray-400">
            {business
              ? "Money the business or project received, such as a client payment."
              : "Withdrawals already on the Withdrawals page are included. Add one here only when it is not listed there."}
          </p>
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>{business ? "Who paid you" : "Withdrawal from"}</span>
          <input
            value={draft.name}
            onChange={(event) => setDraft((current) => ({ ...current, name: event.target.value }))}
            className={fieldClass}
            placeholder={business ? "Client or payer" : "Broker, firm, or account"}
            autoComplete="off"
          />
        </label>

        {business ? (
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Business or project</span>
            <input
              value={draft.projectLabel}
              onChange={(event) =>
                setDraft((current) => ({ ...current, projectLabel: event.target.value }))
              }
              className={fieldClass}
              placeholder="your business/project"
              autoComplete="off"
            />
          </label>
        ) : null}

        <div>
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Amount</span>
            <input
              inputMode="decimal"
              value={draft.amountDigits}
              onChange={(event) => {
                const raw = event.target.value.replace(/[$,\s]/g, "")
                const next = sanitizeMoneyInput(event.target.value)
                if (raw !== "" && next === "") return
                setDraft((current) => ({ ...current, amountDigits: next }))
              }}
              className={fieldClass}
              placeholder="0.00"
            />
          </label>
          <p className={`mt-2 text-lg font-semibold tabular-nums ${READABLE_PRIMARY_CLASS}`}>
            {amount == null || amount <= 0 ? "$0.00" : formatIncomeAmount(amount)}
          </p>
        </div>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Date Received</span>
          <NativeDateInput
            value={draft.dateReceived}
            onChange={(event) =>
              setDraft((current) => ({ ...current, dateReceived: event.currentTarget.value }))
            }
            className="mt-1 w-full"
          />
        </label>

        <RecurrenceChoices
          value={draft.recurrence}
          onChange={(recurrence) => setDraft((current) => ({ ...current, recurrence }))}
        />

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Bank/Card Received On</span>
          <input
            value={draft.paymentLabel}
            onChange={(event) =>
              setDraft((current) => ({ ...current, paymentLabel: event.target.value }))
            }
            className={fieldClass}
            placeholder="Optional label, such as checking"
            autoComplete="off"
          />
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Notes</span>
          <textarea
            value={draft.notes}
            onChange={(event) => setDraft((current) => ({ ...current, notes: event.target.value }))}
            className={fieldClass}
            rows={3}
            placeholder="Optional"
          />
        </label>

        {validationError || error ? (
          <p className="text-sm text-red-300" role="alert">
            {error || validationError}
          </p>
        ) : null}

        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-between">
          {income && onDelete ? (
            confirmDelete ? (
              <button
                type="button"
                disabled={busy}
                onClick={onDelete}
                className="rounded-xl bg-red-500/90 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                Confirm delete
              </button>
            ) : (
              <button
                type="button"
                disabled={busy}
                onClick={() => setConfirmDelete(true)}
                className="rounded-xl px-4 py-2 text-sm font-medium text-red-300 hover:bg-red-500/10"
              >
                Delete
              </button>
            )
          ) : (
            <span />
          )}
          <div className="flex justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              disabled={busy}
              className="rounded-xl border border-white/15 px-4 py-2 text-sm text-gray-200"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={busy || validationError != null}
              onClick={() => onSave(draft)}
              className="rounded-xl bg-emerald-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </div>
    </Modal>
  )
}