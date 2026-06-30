"use client"

import Modal from "@/app/components/ui/Modal"
import EmptyState from "@/app/components/ui/EmptyState"
import { formatPropfirmUsd } from "@/lib/propfirmMetrics"
import {
  formatPayoutDrawdownBehaviorLabel,
  formatPayoutHistoryDate,
  type PayoutHistoryEntry,
} from "@/lib/propfirmPayoutCycles"

const PAYOUT_CARD_CLASS =
  "rounded-lg border border-white/10 bg-white/5 px-3 py-3 transition-colors hover:bg-white/[0.07]"

const PAYOUT_ROW_LABEL_CLASS = "text-xs text-gray-400"
const PAYOUT_ROW_VALUE_CLASS = "text-sm font-medium text-gray-100 tabular-nums"

type PropFirmPayoutHistoryModalProps = {
  open: boolean
  onClose: () => void
  subtitle?: string | null
  payouts: PayoutHistoryEntry[]
  showAccountNames?: boolean
  loading?: boolean
}

function PayoutHistoryCard({
  payout,
  showAccountName,
}: {
  payout: PayoutHistoryEntry
  showAccountName: boolean
}) {
  const note = payout.note?.trim()
  const payoutNumber =
    payout.cycle_number != null ? `Payout #${payout.cycle_number}` : "Payout"

  return (
    <article className={PAYOUT_CARD_CLASS}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          {showAccountName ? (
            <p className="truncate text-sm font-medium text-gray-200">
              {payout.accountName}
            </p>
          ) : null}
          <p
            className={`text-xs uppercase tracking-wide text-gray-500 ${
              showAccountName ? "mt-1" : ""
            }`}
          >
            {payoutNumber}
          </p>
          <p className="mt-0.5 text-lg font-semibold text-emerald-300 tabular-nums">
            {formatPropfirmUsd(Number(payout.payout_amount) || 0)}
          </p>
        </div>
        <p className="shrink-0 text-sm text-gray-300">
          {formatPayoutHistoryDate(payout.ended_at)}
        </p>
      </div>

      <dl className="mt-3 grid gap-2 sm:grid-cols-2">
        <div className="flex flex-col gap-0.5">
          <dt className={PAYOUT_ROW_LABEL_CLASS}>Account Balance After Payout</dt>
          <dd className={PAYOUT_ROW_VALUE_CLASS}>
            {payout.balance_after_payout != null
              ? formatPropfirmUsd(payout.balance_after_payout)
              : "—"}
          </dd>
        </div>
        {!showAccountName ? (
          <div className="flex flex-col gap-0.5">
            <dt className={PAYOUT_ROW_LABEL_CLASS}>Starting Balance For New Cycle</dt>
            <dd className={PAYOUT_ROW_VALUE_CLASS}>
              {payout.balance_after_payout != null
                ? formatPropfirmUsd(payout.balance_after_payout)
                : "—"}
            </dd>
          </div>
        ) : null}
        {!showAccountName ? (
          <div className="flex flex-col gap-0.5 sm:col-span-2">
            <dt className={PAYOUT_ROW_LABEL_CLASS}>Drawdown Reset Mode</dt>
            <dd className="text-sm font-medium text-gray-100">
              {formatPayoutDrawdownBehaviorLabel(payout.drawdown_behavior)}
            </dd>
          </div>
        ) : null}
        {note ? (
          <div className="flex flex-col gap-0.5 sm:col-span-2">
            <dt className={PAYOUT_ROW_LABEL_CLASS}>Notes</dt>
            <dd className="text-sm text-gray-300">{note}</dd>
          </div>
        ) : null}
      </dl>
    </article>
  )
}

export default function PropFirmPayoutHistoryModal({
  open,
  onClose,
  subtitle,
  payouts,
  showAccountNames = false,
  loading = false,
}: PropFirmPayoutHistoryModalProps) {
  return (
    <Modal open={open} onClose={onClose} title="Payout History" size="lg">
      <p className="text-sm leading-relaxed text-gray-300">
        {subtitle ??
          "View every payout recorded for this trading account."}
      </p>

      <div className="mt-5 space-y-3">
        {loading ? (
          <p className="py-8 text-center text-sm text-gray-400">Loading payouts…</p>
        ) : payouts.length === 0 ? (
          <EmptyState
            title="No payouts have been recorded yet."
            description="Once you record your first payout, it will appear here."
          />
        ) : (
          <div className="max-h-[min(60vh,520px)] space-y-3 overflow-y-auto pr-0.5">
            {payouts.map((payout) => (
              <PayoutHistoryCard
                key={payout.id}
                payout={payout}
                showAccountName={showAccountNames}
              />
            ))}
          </div>
        )}
      </div>
    </Modal>
  )
}
