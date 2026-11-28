"use client"

import Modal from "@/app/components/ui/Modal"
import { formatPropFirmMilestoneAccountLabel } from "@/lib/propfirmMilestones"
import type { PropFirmMilestoneAccount } from "@/lib/propfirmMilestones"

type PropFirmEvalContinuanceModalProps = {
  open: boolean
  account: PropFirmMilestoneAccount | null
  busy?: boolean
  onClose: () => void
  onSetUpFundedAccount: () => void
}

export default function PropFirmEvalContinuanceModal({
  open,
  account,
  busy = false,
  onClose,
  onSetUpFundedAccount,
}: PropFirmEvalContinuanceModalProps) {
  const accountLabel = account
    ? formatPropFirmMilestoneAccountLabel(account)
    : "this account"

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Congratulations!"
      size="md"
      footer={
        <button
          type="button"
          disabled={busy}
          onClick={onClose}
          className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-40"
        >
          Not now
        </button>
      }
    >
      <p className="text-sm leading-relaxed text-gray-300">
        Your evaluation has been recorded.
      </p>
      <p className="mt-2 text-sm font-medium text-gray-200">
        Ready to start your funded stage?
      </p>
      <p className="mt-2 text-xs leading-relaxed text-gray-400">
        {accountLabel} stays in your journal with full evaluation history. A new
        funded account uses the same plan slot and starts with fresh prop-firm
        metrics.
      </p>

      <button
        type="button"
        disabled={busy}
        onClick={onSetUpFundedAccount}
        className="mt-4 w-full rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-left transition hover:bg-emerald-500/20 disabled:opacity-40"
      >
        <p className="text-sm font-semibold text-emerald-300">
          Set up funded account
        </p>
        <p className="mt-1 text-xs leading-relaxed text-gray-400">
          Configure rules and account details for your funded stage.
        </p>
      </button>
    </Modal>
  )
}