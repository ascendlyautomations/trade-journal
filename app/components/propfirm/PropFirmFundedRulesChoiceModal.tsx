"use client"

import Modal from "@/app/components/ui/Modal"

type PropFirmFundedRulesChoiceModalProps = {
  open: boolean
  busy?: boolean
  onClose: () => void
  onKeepSameRules: () => void
  onReviewRules: () => void
}

export default function PropFirmFundedRulesChoiceModal({
  open,
  busy = false,
  onClose,
  onKeepSameRules,
  onReviewRules,
}: PropFirmFundedRulesChoiceModalProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Funded Account Rules"
      size="md"
      footer={
        <button
          type="button"
          disabled={busy}
          onClick={onClose}
          className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-40"
        >
          Cancel
        </button>
      }
    >
      <p className="text-sm leading-relaxed text-gray-300">
        Are the funded account rules the same as your evaluation?
      </p>

      <div className="mt-4 space-y-3">
        <button
          type="button"
          disabled={busy}
          onClick={onKeepSameRules}
          className="w-full rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-left transition hover:bg-emerald-500/20 disabled:opacity-40"
        >
          <p className="text-sm font-semibold text-emerald-300">
            Yes, keep the same rules
          </p>
          <p className="mt-1 text-xs leading-relaxed text-gray-400">
            Open the rules editor with your evaluation settings pre-filled. Press
            Continue if nothing changed.
          </p>
        </button>

        <button
          type="button"
          disabled={busy}
          onClick={onReviewRules}
          className="w-full rounded-xl border border-blue-500/30 bg-blue-500/10 px-4 py-3 text-left transition hover:bg-blue-500/20 disabled:opacity-40"
        >
          <p className="text-sm font-semibold text-blue-300">
            Review / Edit Rules
          </p>
          <p className="mt-1 text-xs leading-relaxed text-gray-400">
            Same editor with everything pre-filled. Update profit target, drawdown,
            winning days, consistency, or account balance before continuing.
          </p>
        </button>
      </div>
    </Modal>
  )
}
