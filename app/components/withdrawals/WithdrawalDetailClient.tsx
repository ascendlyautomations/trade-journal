"use client"

import { useMemo, useState } from "react"
import Link from "next/link"
import { useRouter } from "next/navigation"
import AccountPayoutEntryEditorModal from "@/app/components/withdrawals/AccountPayoutEntryEditorModal"
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
  formatPayoutDrawdownBehaviorLabel,
  formatPayoutHistoryDate,
} from "@/lib/propfirmPayoutCycles"
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

  if (!item || !account) {
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
  const displayNotes = stripWithdrawalDrawdownNotePrefix(item.note)
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
        "Delete this withdrawal? Your account value will update. This cannot be undone."
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
          {formatTradingAccountSelectorLabel(account)}
          {" · "}
          {formatTradingAccountModeLabel(account.mode)}
          {" · "}
          {isPropPayoutHistoryItem(item, account)
            ? "Prop payout"
            : isLiveWithdrawalHistoryItem(item, account)
              ? "Live withdrawal"
              : "Withdrawal"}
        </p>
        <p className="mt-1 text-sm text-gray-400">
          {formatPayoutHistoryDate(dateIso)}
        </p>
      </div>

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
            className="rounded-lg border border-red-500/40 px-4 py-2 text-sm font-semibold text-red-200 hover:bg-red-500/10 disabled:opacity-50"
          >
            {deleteBusy ? "Deleting…" : "Delete Withdrawal"}
          </button>
        </div>
      ) : null}

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
