"use client"

import { useEffect, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import ActionButton from "@/app/components/ui/ActionButton"
import {
  type AccountPayoutEntryDraft,
  validateAccountPayoutEntryDraft,
} from "@/lib/accountPayoutEntry"
import { stripWithdrawalDrawdownNotePrefix } from "@/lib/livePersonalDrawdownNote"
import {
  READABLE_FIELD_LABEL_CLASS,
  READABLE_PRIMARY_CLASS,
} from "@/lib/readableTextStyles"

export type AccountPayoutEntryEditorModalProps = {
  open: boolean
  title?: string
  initialDraft: AccountPayoutEntryDraft
  busy?: boolean
  error?: string | null
  onClose: () => void
  onSave: (draft: AccountPayoutEntryDraft) => void
}

export default function AccountPayoutEntryEditorModal({
  open,
  title = "Edit Withdrawal",
  initialDraft,
  busy = false,
  error = null,
  onClose,
  onSave,
}: AccountPayoutEntryEditorModalProps) {
  const [draft, setDraft] = useState(initialDraft)

  useEffect(() => {
    if (open) {
      setDraft({
        ...initialDraft,
        note: stripWithdrawalDrawdownNotePrefix(initialDraft.note),
      })
    }
  }, [open, initialDraft])

  const validationError = validateAccountPayoutEntryDraft(draft)
  const canSave = validationError == null && !busy

  return (
    <Modal open={open} onClose={onClose} title={title}>
      <div className="space-y-4">
        <div>
          <label className={READABLE_FIELD_LABEL_CLASS}>Amount</label>
          <input
            type="text"
            inputMode="decimal"
            value={draft.amountDigits}
            onChange={(e) =>
              setDraft((d) => ({ ...d, amountDigits: e.target.value }))
            }
            className="mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"
            placeholder="0.00"
          />
        </div>

        <div>
          <label className={READABLE_FIELD_LABEL_CLASS}>Date</label>
          <NativeDateInput
            value={draft.payoutDate}
            onChange={(e) =>
              setDraft((d) => ({
                ...d,
                payoutDate: e.currentTarget.value,
              }))
            }
            className="mt-1 w-full"
          />
        </div>

        <div>
          <label className={READABLE_FIELD_LABEL_CLASS}>Notes</label>
          <textarea
            value={draft.note}
            onChange={(e) =>
              setDraft((d) => ({ ...d, note: e.target.value }))
            }
            rows={3}
            className="mt-1 w-full resize-none rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-blue-400/60"
            placeholder="Optional"
          />
        </div>

        {validationError && !error ? (
          <p className="text-sm text-amber-200">{validationError}</p>
        ) : null}
        {error ? <p className="text-sm text-red-300">{error}</p> : null}

        <div className="flex flex-wrap justify-end gap-2 pt-2">
          <button
            type="button"
            onClick={onClose}
            disabled={busy}
            className={`rounded-lg px-4 py-2 text-sm ${READABLE_PRIMARY_CLASS} hover:bg-white/10`}
          >
            Cancel
          </button>
          <ActionButton
            type="button"
            disabled={!canSave}
            onClick={() => onSave(draft)}
            className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600 disabled:opacity-50"
          >
            {busy ? "Saving…" : "Save"}
          </ActionButton>
        </div>
      </div>
    </Modal>
  )
}
