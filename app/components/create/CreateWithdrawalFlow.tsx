"use client"

import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react"
import { useRouter } from "next/navigation"
import IntentPrefetchLink from "@/lib/IntentPrefetchLink"
import NativeDateInput from "@/app/components/ui/NativeDateInput"
import {
  createAccountPayoutEntry,
  fetchManualPayoutEntriesForAccount,
  ledgerTrackedBalance,
  parseWithdrawalAmount,
  type AccountPayoutEntryDraft,
  validateAccountPayoutEntryDraft,
} from "@/lib/accountPayoutEntry"
import {
  supportsManualPayoutLedger,
  supportsRecordPayout,
  supportsWithdrawal,
} from "@/lib/accountPayoutPolicy"
import {
  invalidateAccountsCache,
  isTradesHistoryComplete,
  subscribeAppDataCache,
} from "@/lib/appDataCache"
import { propFirmDetailsHref } from "@/lib/dashboardPropFirmContext"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { parseAccountSizeToNumber } from "@/lib/propfirmMetrics"
import { supabase } from "@/lib/supabaseClient"
import {
  formatTradingAccountModeLabel,
  formatTradingAccountSelectorLabel,
  type AccountRowForDisplay,
} from "@/lib/tradeAccountDisplay"
import { getLocalTodayDateInputValue } from "@/lib/tradeDateValidation"
import { useCachedAccounts, useCachedTrades } from "@/lib/useAppDataCache"
import {
  READABLE_FIELD_LABEL_CLASS,
  READABLE_HELPER_CLASS,
  READABLE_PRIMARY_CLASS,
  READABLE_SECONDARY_CLASS,
} from "@/lib/readableTextStyles"
import { CREATE_ROUTE } from "@/lib/createRoutes"
import { useRegisterCreatePagePrimary } from "@/app/components/create/registerCreatePagePrimary"
import type { CreatePagePrimaryRegistration } from "@/app/components/create/useCreatePagePrimaryAction"
import { parseLivePersonalDrawdownConfigFromAccount } from "@/lib/livePersonalDrawdown"
import type { LiveWithdrawalDrawdownBehavior } from "@/lib/livePersonalDrawdownNote"
import LiveWithdrawalDrawdownPrompt from "@/app/components/create/LiveWithdrawalDrawdownPrompt"

export type CreateWithdrawalFlowProps = {
  userId: string
  registerPrimary: (update: CreatePagePrimaryRegistration) => void
}

type FlowStep = "pick" | "form" | "success"

const EMPTY_DRAFT: AccountPayoutEntryDraft = {
  amountDigits: "",
  payoutDate: getLocalTodayDateInputValue(),
  note: "",
}

function formatWithdrawalBalanceUsd(n: number): string {
  const sign = n < 0 ? "-" : ""
  return `${sign}$${Math.abs(n).toLocaleString("en-US", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`
}

export default function CreateWithdrawalFlow({
  userId,
  registerPrimary,
}: CreateWithdrawalFlowProps) {
  const router = useRouter()
  const { accounts, loading: loadingAccounts } = useCachedAccounts(userId)
  const { trades, loading: loadingTrades } = useCachedTrades(userId, {
    fullHistory: true,
  })
  const tradesHistoryComplete = useSyncExternalStore(
    subscribeAppDataCache,
    () => isTradesHistoryComplete(userId),
    () => false
  )

  const [step, setStep] = useState<FlowStep>("pick")
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(
    null
  )
  const [draft, setDraft] = useState<AccountPayoutEntryDraft>(EMPTY_DRAFT)
  const [formError, setFormError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [savedEntryId, setSavedEntryId] = useState<string | null>(null)
  const [ledgerEntries, setLedgerEntries] = useState<{ amount: number }[]>(
    []
  )
  const [loadingLedger, setLoadingLedger] = useState(false)
  const [drawdownPromptOpen, setDrawdownPromptOpen] = useState(false)

  const withdrawalAccounts = useMemo(() => {
    return (accounts as AccountRowForDisplay[]).filter((account) =>
      supportsWithdrawal(account)
    )
  }, [accounts])

  const selectedAccount = useMemo(() => {
    if (!selectedAccountId) return null
    return (
      (accounts as AccountRowForDisplay[]).find(
        (row) => String(row.id) === selectedAccountId
      ) ?? null
    )
  }, [accounts, selectedAccountId])

  const activePersonalDrawdown = useMemo(
    () => parseLivePersonalDrawdownConfigFromAccount(selectedAccount),
    [selectedAccount]
  )

  const lifetimeRealizedPnL = useMemo(() => {
    if (!selectedAccountId) return 0
    return trades
      .filter(
        (trade) =>
          String(trade.account_id ?? "").trim() === selectedAccountId
      )
      .reduce((sum, trade) => sum + (Number(trade.pnl) || 0), 0)
  }, [selectedAccountId, trades])

  const startingBalance = useMemo(() => {
    if (!selectedAccount) return 0
    return parseAccountSizeToNumber(selectedAccount)
  }, [selectedAccount])

  const parsedAmount = parseWithdrawalAmount(draft.amountDigits)

  const projectedBalance = useMemo(() => {
    if (!selectedAccount || !supportsManualPayoutLedger(selectedAccount)) {
      return null
    }
    return ledgerTrackedBalance(
      startingBalance,
      lifetimeRealizedPnL,
      ledgerEntries,
      parsedAmount ?? 0
    )
  }, [
    ledgerEntries,
    lifetimeRealizedPnL,
    parsedAmount,
    selectedAccount,
    startingBalance,
  ])

  const balancePreviewLoading =
    loadingTrades ||
    !tradesHistoryComplete ||
    loadingLedger

  useEffect(() => {
    if (step !== "form" || !selectedAccountId) return
    let cancelled = false
    setLedgerEntries([])
    setLoadingLedger(true)
    void fetchManualPayoutEntriesForAccount(supabase, selectedAccountId).then(
      (rows) => {
        if (!cancelled) {
          setLedgerEntries(rows)
          setLoadingLedger(false)
        }
      }
    )
    return () => {
      cancelled = true
    }
  }, [selectedAccountId, step])

  const handleSelectAccount = useCallback(
    (account: AccountRowForDisplay) => {
      setFormError(null)
      setDraft({
        ...EMPTY_DRAFT,
        payoutDate: getLocalTodayDateInputValue(),
      })
      const id = String(account.id ?? "").trim()
      if (!id) return

      if (supportsRecordPayout(account)) {
        router.push(propFirmDetailsHref(id))
        return
      }

      setSelectedAccountId(id)
      setStep("form")
    },
    [router]
  )

  const handleBackToPicker = useCallback(() => {
    setFormError(null)
    setSelectedAccountId(null)
    setStep("pick")
    setDraft(EMPTY_DRAFT)
  }, [])

  const submitWithdrawal = useCallback(
    async (liveWithdrawalDrawdownBehavior?: LiveWithdrawalDrawdownBehavior) => {
      if (step !== "form" || !selectedAccountId || !selectedAccount) return

      setSaving(true)
      setFormError(null)
      try {
        const result = await createAccountPayoutEntry({
          supabase,
          userId,
          accountId: selectedAccountId,
          draft,
          account: selectedAccount,
          liveWithdrawalDrawdownBehavior: liveWithdrawalDrawdownBehavior ?? null,
        })
        if (!result.ok) {
          setFormError(result.message)
          return
        }
        invalidateAccountsCache(userId)
        setSavedEntryId(result.entryId)
        setDrawdownPromptOpen(false)
        setStep("success")
      } finally {
        setSaving(false)
      }
    },
    [draft, selectedAccount, selectedAccountId, step, userId]
  )

  const handleSave = useCallback(async () => {
    if (step !== "form" || !selectedAccountId || !selectedAccount) return
    if (isDemoModeActive()) {
      requestDemoSignup("save")
      return
    }

    const validationError = validateAccountPayoutEntryDraft(draft)
    if (validationError) {
      setFormError(validationError)
      return
    }

    if (activePersonalDrawdown) {
      setDrawdownPromptOpen(true)
      return
    }

    await submitWithdrawal()
  }, [
    activePersonalDrawdown,
    draft,
    selectedAccount,
    selectedAccountId,
    step,
    submitWithdrawal,
  ])

  const canSave =
    step === "form" && validateAccountPayoutEntryDraft(draft) == null

  useRegisterCreatePagePrimary({
    enabled: step === "form",
    registerPrimary,
    action: handleSave,
    canAct: canSave,
    busy: saving,
  })

  if (step === "success") {
    return (
      <div className="space-y-4">
        <p className={`text-lg font-semibold ${READABLE_PRIMARY_CLASS}`}>
          Withdrawal recorded
        </p>
        <p className={`text-sm ${READABLE_SECONDARY_CLASS}`}>
          Create an achievement post to share this milestone with the community?
        </p>
        <div className="flex flex-col gap-2 sm:flex-row">
          <button
            type="button"
            className="rounded-lg bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-500"
            onClick={() => router.push(CREATE_ROUTE.achievement)}
          >
            Create Achievement
          </button>
          <button
            type="button"
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-2.5 text-sm font-medium text-gray-200 transition hover:bg-white/10"
            onClick={() => router.push("/app")}
          >
            Not now
          </button>
        </div>
        {savedEntryId ? (
          <p className={`text-xs ${READABLE_HELPER_CLASS}`}>
            Saved to your account ledger — visible in TradeTraxs on iOS and Web.
          </p>
        ) : null}
      </div>
    )
  }

  if (step === "form" && selectedAccount) {
    const accountLabel = formatTradingAccountSelectorLabel(selectedAccount)
    const modeLabel = formatTradingAccountModeLabel(selectedAccount.mode)

    return (
      <div className="space-y-6">
        <LiveWithdrawalDrawdownPrompt
          open={drawdownPromptOpen}
          busy={saving}
          onCancel={() => setDrawdownPromptOpen(false)}
          onChoose={(behavior) => void submitWithdrawal(behavior)}
        />
        <button
          type="button"
          onClick={handleBackToPicker}
          className="text-sm text-blue-300 hover:underline"
        >
          ← Choose a different account
        </button>

        <dl className="grid gap-3 rounded-lg border border-white/10 bg-black/20 px-4 py-3 text-sm sm:grid-cols-2">
          <div>
            <dt className={READABLE_FIELD_LABEL_CLASS}>Account</dt>
            <dd className={`mt-0.5 font-medium ${READABLE_PRIMARY_CLASS}`}>
              {accountLabel}
            </dd>
          </div>
          <div>
            <dt className={READABLE_FIELD_LABEL_CLASS}>Mode</dt>
            <dd className={`mt-0.5 ${READABLE_SECONDARY_CLASS}`}>{modeLabel}</dd>
          </div>
        </dl>

        <div className="space-y-4">
          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Withdrawal amount</span>
            <span className={`ml-2 ${READABLE_HELPER_CLASS}`}>USD</span>
            <input
              type="text"
              inputMode="decimal"
              autoComplete="off"
              placeholder="0"
              value={draft.amountDigits}
              onChange={(event) =>
                setDraft((prev) => ({
                  ...prev,
                  amountDigits: event.target.value.replace(/[^\d.,]/g, ""),
                }))
              }
              className="mt-1.5 h-10 w-full rounded-lg border border-white/10 bg-black/30 px-3 text-sm text-white outline-none transition focus:border-blue-500/40 focus:ring-2 focus:ring-blue-500/20"
            />
          </label>

          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Date</span>
            <NativeDateInput
              value={draft.payoutDate}
              max={getLocalTodayDateInputValue()}
              onChange={(e) =>
                setDraft((prev) => ({ ...prev, payoutDate: e.target.value }))
              }
              className="mt-1.5 h-10 w-full rounded-lg border border-white/10 bg-black/30 px-3 text-sm text-white"
            />
          </label>

          <label className="block">
            <span className={READABLE_FIELD_LABEL_CLASS}>Note</span>
            <span className={`ml-2 ${READABLE_HELPER_CLASS}`}>Optional</span>
            <textarea
              value={draft.note}
              onChange={(event) =>
                setDraft((prev) => ({ ...prev, note: event.target.value }))
              }
              rows={3}
              placeholder="Optional"
              className="mt-1.5 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2 text-sm text-white outline-none transition focus:border-blue-500/40 focus:ring-2 focus:ring-blue-500/20"
            />
          </label>
        </div>

        {projectedBalance != null ? (
          <p className={`text-sm ${READABLE_SECONDARY_CLASS}`}>
            Balance after withdrawal:{" "}
            <span className={`font-semibold tabular-nums ${READABLE_PRIMARY_CLASS}`}>
              {balancePreviewLoading
                ? "Loading…"
                : formatWithdrawalBalanceUsd(projectedBalance)}
            </span>
          </p>
        ) : null}

        {formError ? (
          <p className="text-sm text-red-300" role="alert">
            {formError}
          </p>
        ) : null}
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <p className={`text-sm leading-relaxed ${READABLE_SECONDARY_CLASS}`}>
        Record money taken out of a Live account or a funded prop-firm payout.
        Funded prop-firm accounts open Prop Firm Mode to use the existing Record
        Payout workflow.
      </p>

      {loadingAccounts && withdrawalAccounts.length === 0 ? (
        <p className={`text-sm ${READABLE_HELPER_CLASS}`}>Loading accounts…</p>
      ) : null}

      {!loadingAccounts && withdrawalAccounts.length === 0 ? (
        <div className="rounded-lg border border-white/10 bg-black/20 px-4 py-3">
          <p className={`font-medium ${READABLE_PRIMARY_CLASS}`}>
            No eligible accounts
          </p>
          <p className={`mt-1 text-sm ${READABLE_SECONDARY_CLASS}`}>
            Add a Live or Funded prop-firm account under Settings → Trading
            Accounts.
          </p>
        </div>
      ) : null}

      {withdrawalAccounts.length > 0 ? (
        <ul className="divide-y divide-white/10 rounded-lg border border-white/10">
          {withdrawalAccounts.map((account) => {
            const id = String(account.id ?? "")
            const label = formatTradingAccountSelectorLabel(account)
            const funded = supportsRecordPayout(account)
            return (
              <li key={id}>
                <button
                  type="button"
                  onClick={() => handleSelectAccount(account)}
                  className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left transition hover:bg-white/5"
                >
                  <span className={`min-w-0 text-sm font-medium ${READABLE_PRIMARY_CLASS}`}>
                    {label}
                  </span>
                  <span className={`shrink-0 text-xs ${READABLE_HELPER_CLASS}`}>
                    {funded ? "Prop Firm payout →" : "Manual ledger"}
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      ) : null}

      <p className={`text-sm ${READABLE_SECONDARY_CLASS}`}>
        <IntentPrefetchLink
          href="/withdrawals"
          className="text-blue-300 underline-offset-2 hover:underline"
        >
          Withdrawal history
        </IntentPrefetchLink>
        {" · Affiliate payouts: "}
        <IntentPrefetchLink
          href="/payouts"
          className="text-blue-300 underline-offset-2 hover:underline"
        >
          Affiliate Payouts
        </IntentPrefetchLink>
      </p>
    </div>
  )
}
