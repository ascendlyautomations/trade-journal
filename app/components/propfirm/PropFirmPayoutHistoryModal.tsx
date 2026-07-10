"use client"

import Modal from "@/app/components/ui/Modal"
import EmptyState from "@/app/components/ui/EmptyState"
import { formatPropfirmUsd } from "@/lib/propfirmMetrics"
import {
  formatPayoutDrawdownBehaviorLabel,
  formatPayoutHistoryDate,
  type PayoutHistoryEntry,
} from "@/lib/propfirmPayoutCycles"
import type { Achievement } from "@/lib/achievementTypes"
import { achievementTypeLabel } from "@/lib/achievementTypes"
import {
  buildAccountHistoryTimeline,
  formatAccountHistoryDate,
  type AccountHistoryEvent,
} from "@/lib/accountAchievementHistory"

const PAYOUT_CARD_CLASS =
  "rounded-lg border border-white/10 bg-white/5 px-3 py-3 transition-colors hover:bg-white/[0.07]"

const PAYOUT_ROW_LABEL_CLASS = "text-xs text-gray-400"
const PAYOUT_ROW_VALUE_CLASS = "text-sm font-medium text-gray-100 tabular-nums"

type PropFirmPayoutHistoryModalProps = {
  open: boolean
  onClose: () => void
  subtitle?: string | null
  payouts: PayoutHistoryEntry[]
  achievements?: Achievement[]
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

function AchievementHistoryCard({ achievement }: { achievement: Achievement }) {
  const typeLabel = achievementTypeLabel(achievement.achievement_type)
  const title = achievement.title?.trim() || typeLabel

  return (
    <article className={PAYOUT_CARD_CLASS}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-xs uppercase tracking-wide text-blue-400">
            {typeLabel}
          </p>
          <p className="mt-0.5 truncate text-sm font-semibold text-gray-100">
            {title}
          </p>
        </div>
        <p className="shrink-0 text-sm text-gray-300">
          {formatAccountHistoryDate(
            achievement.achieved_at ?? achievement.created_at
          )}
        </p>
      </div>
      {achievement.value_numeric != null && achievement.value_numeric > 0 ? (
        <p className="mt-2 text-lg font-semibold text-emerald-300 tabular-nums">
          {formatPropfirmUsd(achievement.value_numeric)}
        </p>
      ) : null}
    </article>
  )
}

function AccountHistoryCard({
  event,
  showAccountName,
}: {
  event: AccountHistoryEvent
  showAccountName: boolean
}) {
  if (event.kind === "payout") {
    return (
      <PayoutHistoryCard payout={event.payout} showAccountName={showAccountName} />
    )
  }

  return <AchievementHistoryCard achievement={event.achievement} />
}

export default function PropFirmPayoutHistoryModal({
  open,
  onClose,
  subtitle,
  payouts,
  achievements = [],
  showAccountNames = false,
  loading = false,
}: PropFirmPayoutHistoryModalProps) {
  const timeline = buildAccountHistoryTimeline(payouts, achievements)

  return (
    <Modal open={open} onClose={onClose} title="Account History" size="lg">
      <p className="text-sm leading-relaxed text-gray-300">
        {subtitle ??
          "View payouts and achievements recorded for this trading account."}
      </p>

      <div className="mt-5 space-y-3">
        {loading ? (
          <p className="py-8 text-center text-sm text-gray-400">Loading history…</p>
        ) : timeline.length === 0 ? (
          <EmptyState
            title="No account history yet."
            description="Recorded payouts and linked achievements will appear here."
          />
        ) : (
          <div className="max-h-[min(60vh,520px)] space-y-3 overflow-y-auto pr-0.5">
            {timeline.map((event) => (
              <AccountHistoryCard
                key={
                  event.kind === "payout"
                    ? `payout-${event.payout.id}`
                    : `achievement-${event.achievement.id}`
                }
                event={event}
                showAccountName={showAccountNames}
              />
            ))}
          </div>
        )}
      </div>
    </Modal>
  )
}
