"use client"

import { useEffect, useMemo, useState } from "react"
import RecurrenceChoices from "@/app/components/propFirmExpenses/RecurrenceChoices"
import Modal from "@/app/components/ui/Modal"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  EXPENSE_TRACKER_KINDS,
  PROP_FIRM_EXPENSE_TYPES,
  draftFromExpense,
  emptyPropFirmExpenseDraft,
  formatCents,
  parseMoneyToCents,
  propFirmExpenseTypeLabel,
  sanitizeMoneyInput,
  sanitizeQuantityInput,
  totalCostCents,
  validatePropFirmExpenseDraft,
  type PropFirmExpenseAccountOption,
  type PropFirmExpenseDraft,
  type PropFirmExpenseRecord,
} from "@/lib/propFirmExpenses"
import {
  READABLE_FIELD_LABEL_CLASS,
  READABLE_PRIMARY_CLASS,
} from "@/lib/readableTextStyles"

const fieldClass =
  "mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"

export default function PropFirmExpenseEditorModal({
  open,
  expense,
  accounts,
  categories = [],
  busy = false,
  error = null,
  onClose,
  onSave,
  onDelete,
}: {
  open: boolean
  expense: PropFirmExpenseRecord | null
  accounts: PropFirmExpenseAccountOption[]
  categories?: string[]
  busy?: boolean
  error?: string | null
  onClose: () => void
  onSave: (draft: PropFirmExpenseDraft) => void
  onDelete?: () => void
}) {
  const [draft, setDraft] = useState<PropFirmExpenseDraft>(emptyPropFirmExpenseDraft())
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [newCategory, setNewCategory] = useState("")

  useEffect(() => {
    if (!open) return
    setDraft(expense ? draftFromExpense(expense) : emptyPropFirmExpenseDraft())
    setConfirmDelete(false)
    setNewCategory("")
  }, [open, expense])

  const validationError = validatePropFirmExpenseDraft(draft)
  const total = useMemo(() => {
    const cost = parseMoneyToCents(draft.costDigits)
    const quantity = Number(draft.quantityDigits)
    if (cost == null || cost <= 0 || !Number.isInteger(quantity) || quantity < 1) return null
    return totalCostCents(cost, quantity)
  }, [draft.costDigits, draft.quantityDigits])

  const linkedLocked = expense?.source === "account_purchase"
  const propFirm = draft.trackerKind === "prop_firm"
  const categoryOptions = [...new Set(categories.map((name) => name.trim()).filter(Boolean))]

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={expense ? "Edit Expense" : "Add Expense"}
    >
      <div className="space-y-4">
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Expense Type</span>
          <select
            value={draft.trackerKind}
            disabled={linkedLocked}
            onChange={(event) =>
              setDraft((current) => ({
                ...current,
                trackerKind: event.target.value as PropFirmExpenseDraft["trackerKind"],
                accountId: event.target.value === "prop_firm" ? current.accountId : null,
              }))
            }
            className={fieldClass}
          >
            {EXPENSE_TRACKER_KINDS.map((kind) => (
              <option key={kind.value} value={kind.value}>
                {kind.label}
              </option>
            ))}
          </select>
        </label>
        {propFirm ? (
        <>
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Prop Firm Name</span>
          <input
            value={draft.propFirmName}
            onChange={(event) =>
              setDraft((current) => ({ ...current, propFirmName: event.target.value }))
            }
            className={fieldClass}
            placeholder="Apex, Topstep, Take Profit Trader"
            autoComplete="off"
          />
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Prop Firm Category</span>
          <select
            value={draft.expenseType}
            onChange={(event) =>
              setDraft((current) => ({
                ...current,
                expenseType: event.target.value as PropFirmExpenseDraft["expenseType"],
              }))
            }
            className={fieldClass}
          >
            {PROP_FIRM_EXPENSE_TYPES.map((type) => (
              <option key={type.value} value={type.value}>
                {type.label}
              </option>
            ))}
          </select>
        </label>
        </>
        ) : (
          <>
            <label className="block">
              <span className={READABLE_FIELD_LABEL_CLASS}>Vendor or name</span>
              <input
                value={draft.propFirmName}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, propFirmName: event.target.value }))
                }
                className={fieldClass}
                placeholder="Vendor, tool, or expense name"
                autoComplete="off"
              />
            </label>
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
            <label className="block">
              <span className={READABLE_FIELD_LABEL_CLASS}>Category</span>
              <select
                value={categoryOptions.includes(draft.customCategory) ? draft.customCategory : ""}
                onChange={(event) =>
                  setDraft((current) => ({ ...current, customCategory: event.target.value }))
                }
                className={fieldClass}
              >
                <option value="">Choose a category</option>
                {categoryOptions.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
              <input
                value={newCategory}
                onChange={(event) => {
                  const next = event.target.value
                  setNewCategory(next)
                  setDraft((current) => ({ ...current, customCategory: next }))
                }}
                className={fieldClass}
                placeholder="Or create a category"
                autoComplete="off"
              />
            </label>
          </>
        )}

        <div className="grid grid-cols-2 gap-3">
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>{propFirm ? "Cost Per Account" : "Amount"}</span>
            <input
              inputMode="decimal"
              value={draft.costDigits}
              onChange={(event) => {
                const raw = event.target.value.replace(/[$,\s]/g, "")
                const next = sanitizeMoneyInput(event.target.value)
                if (raw !== "" && next === "") return
                setDraft((current) => ({ ...current, costDigits: next }))
              }}
              className={fieldClass}
              placeholder="0.00"
            />
          </label>
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>{propFirm ? "Quantity of Accounts" : "Quantity"}</span>
            <input
              inputMode="numeric"
              value={draft.quantityDigits}
              onChange={(event) =>
                setDraft((current) => ({
                  ...current,
                  quantityDigits: sanitizeQuantityInput(event.target.value),
                }))
              }
              className={fieldClass}
              placeholder="1"
            />
          </label>
        </div>

        <div>
          <span className={READABLE_FIELD_LABEL_CLASS}>Total Cost</span>
          <p className={`mt-1 text-lg font-semibold tabular-nums ${READABLE_PRIMARY_CLASS}`}>
            {total == null ? "$0.00" : formatCents(total)}
          </p>
        </div>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Purchase Date</span>
          <NativeDateInput
            value={draft.datePaid}
            onChange={(event) =>
              setDraft((current) => ({
                ...current,
                datePaid: event.currentTarget.value,
              }))
            }
            className="mt-1 w-full"
          />
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Bank/Card Paid With</span>
          <input
            value={draft.paymentLabel}
            onChange={(event) =>
              setDraft((current) => ({ ...current, paymentLabel: event.target.value }))
            }
            className={fieldClass}
            placeholder="Optional label, such as Visa"
            autoComplete="off"
          />
        </label>

        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Notes</span>
          <textarea
            value={draft.notes}
            onChange={(event) =>
              setDraft((current) => ({ ...current, notes: event.target.value }))
            }
            className={fieldClass}
            rows={3}
            placeholder="Optional"
          />
        </label>

        <RecurrenceChoices
          value={draft.recurrence}
          onChange={(recurrence) => setDraft((current) => ({ ...current, recurrence }))}
        />

        {propFirm ? (
        <label className="block">
          <span className={READABLE_FIELD_LABEL_CLASS}>Linked Trading Account</span>
          {linkedLocked ? (
            <p className="mt-1 text-sm text-gray-300">
              {expense?.accountId
                ? (accounts.find((account) => account.id === expense.accountId)?.name ??
                  "Linked account")
                : "Unlinked. The account was removed and this expense was kept."}
            </p>
          ) : (
            <select
              value={draft.accountId ?? ""}
              onChange={(event) =>
                setDraft((current) => ({
                  ...current,
                  accountId: event.target.value || null,
                }))
              }
              className={fieldClass}
            >
              <option value="">None</option>
              {accounts.map((account) => (
                <option key={account.id} value={account.id}>
                  {account.name}
                </option>
              ))}
            </select>
          )}
          {linkedLocked ? (
            <p className="mt-1 text-xs text-gray-400">
              This expense stays linked to the account it was created with.
              Deleting the account keeps this history.
            </p>
          ) : null}
        </label>
        ) : null}

        {expense ? (
          <p className="text-xs text-gray-400">
            {propFirmExpenseTypeLabel(expense.expenseType)}
            {expense.source === "account_purchase" ? " · From account setup" : ""}
          </p>
        ) : null}

        {validationError || error ? (
          <p className="text-sm text-red-300" role="alert">
            {error || validationError}
          </p>
        ) : null}

        <div className="flex flex-col-reverse gap-2 sm:flex-row sm:items-center sm:justify-between">
          {expense && onDelete ? (
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
              className="rounded-xl bg-blue-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              {busy ? "Saving…" : "Save"}
            </button>
          </div>
        </div>
      </div>
    </Modal>
  )
}
