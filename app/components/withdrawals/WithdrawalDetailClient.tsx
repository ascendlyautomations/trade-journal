"use client"

import { useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import AccountPayoutEntryEditorModal from "@/app/components/withdrawals/AccountPayoutEntryEditorModal"
import PropFirmPayoutAssignmentSection from "@/app/components/withdrawals/PropFirmPayoutAssignmentSection"
import Modal from "@/app/components/ui/Modal"
import {
  deleteAccountPayoutEntry,
  type AccountPayoutEntryDraft,
  updateAccountPayoutEntry,
} from "@/lib/accountPayoutEntry"
import { formatCurrency } from "@/lib/formatCurrency"
import {
  isLiveWithdrawalHistoryItem,
  isPropPayoutHistoryItem,
  type PayoutHistoryAccount,
  type PayoutHistoryItem,
} from "@/lib/payoutHistory"
import {
  deletePropPayout,
  formatPayoutDrawdownBehaviorLabel,
  formatPayoutHistoryDate,
} from "@/lib/propfirmPayoutCycles"
import type { PayoutDrawdownBehavior } from "@/lib/propfirmMetrics"
import {
  formatTradingAccountModeLabel,
  formatTradingAccountSelectorLabel,
} from "@/lib/tradeAccountDisplay"
import {
  parseWithdrawalDrawdownBehaviorFromNote,
  stripWithdrawalDrawdownNotePrefix,
} from "@/lib/livePersonalDrawdownNote"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/useUserProfile"
import { useWithdrawalsHistory } from "@/lib/useWithdrawalsHistory"

function screenTitle(
  item: PayoutHistoryItem,
  account: PayoutHistoryAccount | undefined
): string {
  return isPropPayoutHistoryItem(item, account) ? "Payout" : "Withdrawal"
}

function liveDrawdownBehaviorLabel(note: string | null): string | null {
  const behavior = parseWithdrawalDrawdownBehaviorFromNote(note)
  if (behavior === "reset_to_account") {
    return "Personal drawdown baseline reset after withdrawal"
  }
  if (behavior === "keep_trailing") {
    return "Trailing drawdown unchanged"
  }
  return null
}

type WithdrawalDetailClientProps = {
  historyItemId: string
}

export default function WithdrawalDetailClient({
  historyItemId,
}: WithdrawalDetailClientProps) {
  const router = useRouter()
  const { user } = useUserProfile()
  const { loading, items, accountsById, refresh } = useWithdrawalsHistory(
    user?.id
  )

  const item = useMemo(
    () => items.find((row) => row.id === historyItemId) ?? null,
    [items, historyItemId]
  )
  const account = item ? accountsById[item.accountId] : undefined

  const [editorOpen, setEditorOpen] = useState(false)
  const [editorBusy, setEditorBusy] = useState(false)
  const [editorError, setEditorError] = useState<string | null>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const [drawdownChoiceOpen, setDrawdownChoiceOpen] = useState(false)
  const [drawdownBehavior, setDrawdownBehavior] =
    useState<PayoutDrawdownBehavior>("reset_to_account")

  const dateIso =
    item?.source === "fundedCycle"
      ? item.cycle?.ended_at ?? item.cycle?.started_at ?? null
      : item?.payoutDate
        ? `${item.payoutDate}T12:00:00.000Z`
        : item
          ? new Date(item.dateMs).toISOString()
          : null

  const editorInitialDraft: AccountPayoutEntryDraft | null = useMemo(() => {
    if (!item?.ledgerEntryId || !item.payoutDate) return null
    return {
      amountDigits: String(item.amount),
      payoutDate: item.payoutDate,
      note: stripWithdrawalDrawdownNotePrefix(item.note),
    }
  }, [item])

  if (!user?.id) {
    return <p className="text-sm text-gray-400">Sign in to view withdrawals.</p>
  }

  if (loading && !item) {
    return <p className="text-sm text-gray-400">Loading withdrawal…</p>
  }

  const fromAchievement =
    item?.source === "achievementProp" || item?.source === "achievementLive"

  if (!item || (!account && !fromAchievement)) {
    return (
      <div className="space-y-4">
        <p className="text-sm text-gray-300">
          This withdrawal could not be loaded.
        </p>
        <Link href="/withdrawals" className="text-sm text-blue-300 hover:underline">
          ← Withdrawals
        </Link>
      </div>
    )
  }

  const title = screenTitle(item, account)
  const accountLabel = account
    ? `${formatTradingAccountSelectorLabel(account)} · ${formatTradingAccountModeLabel(account.mode)} · `
    : ""
  const displayNotes = fromAchievement
    ? null
    : stripWithdrawalDrawdownNotePrefix(item.note)
  const liveDdLabel = isLiveWithdrawalHistoryItem(item, account)
    ? liveDrawdownBehaviorLabel(item.note)
    : null

  async function handleSaveEdit(draft: AccountPayoutEntryDraft) {
    if (!user?.id || !item?.ledgerEntryId) return
    setEditorBusy(true)
    setEditorError(null)
    const result = await updateAccountPayoutEntry({
      supabase,
      userId: user.id,
      entryId: item.ledgerEntryId,
      draft,
      priorNote: item.note,
    })
    setEditorBusy(false)
    if (!result.ok) {
      setEditorError(result.message)
      return
    }
    setEditorOpen(false)
    await refresh()
  }

  async function handleDelete() {
    if (!user?.id || !item?.ledgerEntryId) return
    if (
      !window.confirm(
        `Delete this withdrawal? ${formatCurrency(item.amount)} goes back on the account balance. This cannot be undone.`
      )
    ) {
      return
    }
    setDeleteBusy(true)
    setActionError(null)
    const result = await deleteAccountPayoutEntry(
      supabase,
      user.id,
      item.ledgerEntryId
    )
    setDeleteBusy(false)
    if (!result.ok) {
      setActionError(result.message)
      return
    }
    router.push("/withdrawals")
    router.refresh()
  }

  async function handleDeletePropPayout() {
    if (!user?.id || !item || item.source !== "fundedCycle") return
    const cycleId = item.id.replace(/^cycle:/, "")
    setDeleteBusy(true)
    setActionError(null)
    const result = await deletePropPayout(supabase, cycleId, drawdownBehavior)
    setDeleteBusy(false)
    if (!result.ok) {
      setActionError(result.message)
      return
    }
    setDrawdownChoiceOpen(false)
    router.push("/withdrawals")
    router.refresh()
  }

  async function handleDeleteAchievementPayout() {
    if (!user?.id || !item?.id.startsWith("achievement:")) return
    if (
      !window.confirm(
        "Delete this payout from Withdrawals? The profile post for it is removed too."
      )
    ) {
      return
    }
    const achievementId = item.id.slice("achievement:".length)
    setDeleteBusy(true)
    setActionError(null)
    const { error } = await supabase
      .from("achievements")
      .delete()
      .eq("id", achievementId)
      .eq("user_id", user.id)
    setDeleteBusy(false)
    if (error) {
      setActionError(error.message)
      return
    }
    router.push("/withdrawals")
    router.refresh()
  }

  const canDeleteProp = item.source === "fundedCycle"
  const canDeleteAchievement =
    item.source === "achievementProp" || item.source === "achievementLive"

  return (
    <div className="space-y-6">
      <div>
        <Link
          href="/withdrawals"
          className="text-sm text-blue-300 hover:text-blue-200"
        >
          ← Withdrawals
        </Link>
        <h1 className="mt-3 text-2xl font-bold text-white">{title}</h1>
      </div>

      <div className="rounded-xl border border-white/10 bg-white/5 p-5">
        <p className="text-3xl font-semibold tabular-nums text-white">
          {formatCurrency(item.amount)}
        </p>
        <p className="mt-2 text-sm text-gray-300">
          {accountLabel}
          {isPropPayoutHistoryItem(item, account)
            ? "Prop payout"
            : isLiveWithdrawalHistoryItem(item, account)
              ? "Live withdrawal"
              : "Withdrawal"}
          {fromAchievement && !account && item.note ? ` · ${item.note}` : ""}
        </p>
        <p className="mt-1 text-sm text-gray-400">
          {formatPayoutHistoryDate(dateIso)}
        </p>
      </div>

      {(isPropPayoutHistoryItem(item, account) && account) || fromAchievement ? (
        <PropFirmPayoutAssignmentSection
          userId={user.id}
          payoutKey={item.id}
          accountId={item.accountId}
          accountName={account?.name}
        />
      ) : null}

      {item.cycle ? (
        <dl className="space-y-3 rounded-xl border border-white/10 bg-white/5 p-5 text-sm">
          {item.cycle.balance_before_payout != null ? (
            <div className="flex justify-between gap-4">
              <dt className="text-gray-400">Balance before</dt>
              <dd className="font-medium tabular-nums text-white">
                {formatCurrency(item.cycle.balance_before_payout)}
              </dd>
            </div>
          ) : null}
          {item.cycle.balance_after_payout != null ? (
            <div className="flex justify-between gap-4">
              <dt className="text-gray-400">Balance after</dt>
              <dd className="font-medium tabular-nums text-white">
                {formatCurrency(item.cycle.balance_after_payout)}
              </dd>
            </div>
          ) : null}
          {item.cycle.drawdown_behavior ? (
            <div className="flex justify-between gap-4">
              <dt className="text-gray-400">Drawdown</dt>
              <dd className="text-right text-white">
                {formatPayoutDrawdownBehaviorLabel(item.cycle.drawdown_behavior)}
              </dd>
            </div>
          ) : null}
          {item.cycle.cycle_number != null ? (
            <div className="flex justify-between gap-4">
              <dt className="text-gray-400">Cycle</dt>
              <dd className="text-white">{item.cycle.cycle_number}</dd>
            </div>
          ) : null}
        </dl>
      ) : null}

      {liveDdLabel ? (
        <p className="text-sm text-gray-400">{liveDdLabel}</p>
      ) : null}

      {displayNotes ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-sm font-semibold text-white">Notes</h2>
          <p className="mt-2 whitespace-pre-wrap text-sm text-gray-300">
            {displayNotes}
          </p>
        </div>
      ) : null}

      {item.imageUrl ? (
        <div className="rounded-xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-sm font-semibold text-white">Picture</h2>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={item.imageUrl}
            alt=""
            className="mt-3 max-h-80 w-full rounded-lg object-contain"
          />
        </div>
      ) : null}

      {actionError ? (
        <p className="text-sm text-red-300">{actionError}</p>
      ) : null}

      {item.isEditable ? (
        <div className="flex flex-wrap gap-3">
          <button
            type="button"
            onClick={() => {
              setEditorError(null)
              setEditorOpen(true)
            }}
            className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-600"
          >
            Edit
          </button>
          <button
            type="button"
            onClick={() => void handleDelete()}
            disabled={deleteBusy}
            className="rounded-lg bg-red-500/15 px-4 py-2 text-sm font-semibold text-red-200 hover:bg-red-500/25 disabled:opacity-50"
          >
            {deleteBusy ? "Deleting…" : "Delete Withdrawal"}
          </button>
        </div>
      ) : null}

      {canDeleteProp ? (
        <button
          type="button"
          onClick={() => {
            setDrawdownBehavior(item.cycle?.drawdown_behavior ?? "reset_to_account")
            setActionError(null)
            setDrawdownChoiceOpen(true)
          }}
          disabled={deleteBusy}
          className="rounded-lg bg-red-500/15 px-4 py-2 text-sm font-semibold text-red-200 hover:bg-red-500/25 disabled:opacity-50"
        >
          Delete payout
        </button>
      ) : null}

      {canDeleteAchievement ? (
        <button
          type="button"
          onClick={() => void handleDeleteAchievementPayout()}
          disabled={deleteBusy}
          className="rounded-lg bg-red-500/15 px-4 py-2 text-sm font-semibold text-red-200 hover:bg-red-500/25 disabled:opacity-50"
        >
          {deleteBusy ? "Deleting…" : "Delete payout"}
        </button>
      ) : null}

      <Modal
        open={drawdownChoiceOpen}
        onClose={() => {
          if (!deleteBusy) setDrawdownChoiceOpen(false)
        }}
        title="Delete payout"
        footer={
          <div className="flex justify-end gap-3">
            <button
              type="button"
              disabled={deleteBusy}
              onClick={() => setDrawdownChoiceOpen(false)}
              className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 hover:bg-white/10 disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              disabled={deleteBusy}
              onClick={() => void handleDeletePropPayout()}
              className="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500 disabled:opacity-50"
            >
              {deleteBusy ? "Deleting…" : "Delete payout"}
            </button>
          </div>
        }
      >
        <p className="text-sm leading-relaxed text-gray-300">
          {formatCurrency(item.amount)} goes back on the account balance. Where
          should the drawdown move after this payout is deleted?
        </p>
        {actionError ? (
          <p className="mt-3 text-sm text-red-300">{actionError}</p>
        ) : null}
        <div className="mt-4 space-y-3">
          <label
            className={`block cursor-pointer rounded-lg border px-3 py-3 ${
              drawdownBehavior === "reset_to_account"
                ? "border-blue-500/40 bg-blue-500/10"
                : "border-white/10 bg-white/5"
            }`}
          >
            <span className="flex items-start gap-2.5">
              <input
                type="radio"
                name="delete-drawdown"
                checked={drawdownBehavior === "reset_to_account"}
                onChange={() => setDrawdownBehavior("reset_to_account")}
                className="mt-1"
              />
              <span>
                <span className="block text-sm font-medium text-gray-100">
                  Reset drawdown to account value
                </span>
                <span className="mt-1 block text-xs text-gray-400">
                  The drawdown floor moves back to the account starting balance.
                </span>
              </span>
            </span>
          </label>
          <label
            className={`block cursor-pointer rounded-lg border px-3 py-3 ${
              drawdownBehavior === "keep_trailing"
                ? "border-blue-500/40 bg-blue-500/10"
                : "border-white/10 bg-white/5"
            }`}
          >
            <span className="flex items-start gap-2.5">
              <input
                type="radio"
                name="delete-drawdown"
                checked={drawdownBehavior === "keep_trailing"}
                onChange={() => setDrawdownBehavior("keep_trailing")}
                className="mt-1"
              />
              <span>
                <span className="block text-sm font-medium text-gray-100">
                  Keep trailing drawdown
                </span>
                <span className="mt-1 block text-xs text-gray-400">
                  The drawdown floor stays at its current trailing level.
                </span>
              </span>
            </span>
          </label>
        </div>
      </Modal>

      {editorInitialDraft ? (
        <AccountPayoutEntryEditorModal
          open={editorOpen}
          initialDraft={editorInitialDraft}
          busy={editorBusy}
          error={editorError}
          onClose={() => setEditorOpen(false)}
          onSave={(draft) => void handleSaveEdit(draft)}
        />
      ) : null}
    </div>
  )
}
