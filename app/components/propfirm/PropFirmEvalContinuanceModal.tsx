"use client"

import Modal from "@/app/components/ui/Modal"
import { formatPropFirmMilestoneAccountLabel } from "@/lib/propfirmMilestones"
import type { PropFirmMilestoneAccount } from "@/lib/propfirmMilestones"

type PropFirmEvalContinuanceModalProps = {
  open: boolean
  account: PropFirmMilestoneAccount | null
  busy?: boolean
  onClose: () => void
  onConvertToFunded: () => void
  onCreateNewFundedAccount: () => void
}

export default function PropFirmEvalContinuanceModal({
  open,
  account,
  busy = false,
  onClose,
  onConvertToFunded,
  onCreateNewFundedAccount,
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
        How would you like to continue?
      </p>

      <div className="mt-4 space-y-3">
        <button
          type="button"
          disabled={busy}
          onClick={onConvertToFunded}
          className="w-full rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-4 py-3 text-left transition hover:bg-emerald-500/20 disabled:opacity-40"
        >
          <p className="text-sm font-semibold text-emerald-300">
            Convert this Evaluation into my Funded account
          </p>
          <p className="mt-1 text-xs leading-relaxed text-gray-400">
            Update {accountLabel} from Evaluation to Funded. All trades, analytics,
            and history stay on this account.
          </p>
        </button>

        <button
          type="button"
          disabled={busy}
          onClick={onCreateNewFundedAccount}
          className="w-full rounded-xl border border-blue-500/30 bg-blue-500/10 px-4 py-3 text-left transition hover:bg-blue-500/20 disabled:opacity-40"
        >
          <p className="text-sm font-semibold text-blue-300">
            My prop firm issued me a NEW funded account
          </p>
          <p className="mt-1 text-xs leading-relaxed text-gray-400">
            Keep your evaluation account unchanged for history and start a separate
            funded account. Trades are not moved automatically.
          </p>
        </button>
      </div>
    </Modal>
  )
}
