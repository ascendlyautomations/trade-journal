"use client"

import {
  READABLE_HELPER_CLASS,
  READABLE_PRIMARY_CLASS,
  READABLE_SECONDARY_CLASS,
} from "@/lib/readableTextStyles"
import type { LiveWithdrawalDrawdownBehavior } from "@/lib/livePersonalDrawdownNote"

export type LiveWithdrawalDrawdownPromptProps = {
  open: boolean
  busy: boolean
  onChoose: (behavior: LiveWithdrawalDrawdownBehavior) => void
  onCancel: () => void
}

export default function LiveWithdrawalDrawdownPrompt({
  open,
  busy,
  onChoose,
  onCancel,
}: LiveWithdrawalDrawdownPromptProps) {
  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-[120] flex items-end justify-center bg-black/60 p-4 sm:items-center"
      role="dialog"
      aria-labelledby="live-withdrawal-dd-title"
      aria-modal="true"
    >
      <div className="w-full max-w-md rounded-xl border border-white/10 bg-[#0f172a] p-5 shadow-xl">
        <h2
          id="live-withdrawal-dd-title"
          className={`text-lg font-semibold ${READABLE_PRIMARY_CLASS}`}
        >
          Update Drawdown After Withdrawal?
        </h2>
        <p className={`mt-2 text-sm ${READABLE_SECONDARY_CLASS}`}>
          This withdrawal changes your tracked account balance. Choose how your
          personal drawdown floor should respond (informational only).
        </p>

        <div className="mt-4 space-y-3">
          <button
            type="button"
            disabled={busy}
            onClick={() => onChoose("reset_to_account")}
            className="w-full rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:bg-white/10 disabled:opacity-50"
          >
            <p className={`text-sm font-semibold ${READABLE_PRIMARY_CLASS}`}>
              Reset to New Balance
            </p>
            <p className={`mt-1 text-xs leading-snug ${READABLE_HELPER_CLASS}`}>
              Sets a new drawdown baseline at your balance after this withdrawal.
              Trailing high-water mark resets to that same level.
            </p>
          </button>
          <button
            type="button"
            disabled={busy}
            onClick={() => onChoose("keep_trailing")}
            className="w-full rounded-lg border border-white/10 bg-white/5 px-4 py-3 text-left transition hover:bg-white/10 disabled:opacity-50"
          >
            <p className={`text-sm font-semibold ${READABLE_PRIMARY_CLASS}`}>
              Keep Existing Limit
            </p>
            <p className={`mt-1 text-xs leading-snug ${READABLE_HELPER_CLASS}`}>
              Keeps your current absolute drawdown floor and trailing high-water
              mark unchanged.
            </p>
          </button>
        </div>

        <button
          type="button"
          disabled={busy}
          onClick={onCancel}
          className="mt-4 w-full rounded-lg py-2 text-sm text-gray-400 hover:text-gray-200 disabled:opacity-50"
        >
          Cancel
        </button>
      </div>
    </div>
  )
}
