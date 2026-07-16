"use client"

import dynamic from "next/dynamic"
import { useCallback, useEffect, useRef, useState } from "react"
import TradeAccountPicker, {
  type TradeAccountOption,
} from "@/app/components/TradeAccountPicker"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import { supabase } from "@/lib/supabaseClient"
import { isProActive } from "@/lib/subscription"
import { FREE_PLAN_ACCOUNT_LIMIT, assertCanCreateTradingAccount } from "@/lib/tradingAccounts"
import { assertRequiredAccountValue } from "@/lib/createAccountForm"
import { countTradeEntryEnabledAccounts } from "@/lib/freePlanAccountSlots"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { MODAL_PANEL_MAX_HEIGHT_CLASS, useModalScrollLock } from "@/app/components/ui/modalLayout"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"
import { useUserProfile } from "@/lib/useUserProfile"

const CsvImportPanel = dynamic(() => import("@/app/components/CsvImportPanel"), {
  ssr: false,
})

const CSV_INPUT_ID = "post-setup-csv-import"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

type Props = {
  open: boolean
  onComplete: () => void | Promise<void>
}

export default function PostSetupImportModal({ open, onComplete }: Props) {
  const { showPopup, closePopup, feedbackModalProps } = useFeedbackPopup()
  const { user, profile } = useUserProfile()
  const importCompletePendingRef = useRef(false)
  const creatingAccountRef = useRef(false)
  const [entered, setEntered] = useState(false)
  const [accounts, setAccounts] = useState<TradeAccountOption[]>([])
  const [selectedAccount, setSelectedAccount] = useState<TradeAccountOption | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [canCreateMoreAccounts, setCanCreateMoreAccounts] = useState(true)
  useModalScrollLock(open)

  useEffect(() => {
    if (!open) {
      setEntered(false)
      return
    }
    const id = window.requestAnimationFrame(() => setEntered(true))
    return () => window.cancelAnimationFrame(id)
  }, [open])

  useEffect(() => {
    if (!open) return

    async function loadAccounts() {
      if (!user?.id) return

      const { data, error } = await supabase
        .from("accounts")
        .select("*")
        .eq("user_id", user.id)

      if (error) {
        console.error(error)
        return
      }

      const formatted = (data || []).map((acc) => ({
        name: acc.name,
        size: acc.account_size,
        id: acc.id,
        account_number: acc.account_number ?? null,
        mode: acc.mode,
        category: acc.category,
        can_add_trades: acc.can_add_trades !== false,
      }))

      setAccounts(formatted)
      const userIsPro = isProActive(profile)
      setCanCreateMoreAccounts(
        userIsPro ||
          countTradeEntryEnabledAccounts(formatted) < FREE_PLAN_ACCOUNT_LIMIT
      )
    }

    void loadAccounts()
  }, [open, user?.id, profile])

  async function handleSkip() {
    await onComplete()
  }

  const handleFeedbackClose = useCallback(() => {
    closePopup()
    if (importCompletePendingRef.current) {
      importCompletePendingRef.current = false
      void onComplete()
    }
  }, [closePopup, onComplete])

  function handleImportSuccess(info: {
    count: number
    skipped: number
    errorSummary?: string
  }) {
    const base = feedbackPresets.importSuccess(info.count, info.skipped)
    let message = base.message as string
    if (info.errorSummary) message += `\n\n${info.errorSummary}`
    importCompletePendingRef.current = true
    showPopup({ ...base, message })
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    if (creatingAccountRef.current) return
    creatingAccountRef.current = true

    try {
    if (!user?.id) return

    const userIsPro = isProActive(profile)
    if (!userIsPro) {
      const gate = await assertCanCreateTradingAccount(supabase, user.id, profile)
      if (!gate.ok) {
        setCanCreateMoreAccounts(false)
        showPopup(feedbackPresets.accountLimit())
        return
      }
    }

    const sizeGate = assertRequiredAccountValue(newAccount.size)
    if (!sizeGate.ok) {
      showPopup(persistentError("Account Value Required", sizeGate.message))
      return
    }

    const { data, error } = await supabase
      .from("accounts")
      .insert([
        {
          user_id: user.id,
          name: newAccount.name,
          account_size: sizeGate.value,
          account_number: newAccount.id,
          category: newAccount.category,
          mode: newAccount.mode,
          is_active: true,
          can_add_trades: true,
          consistency: newAccount.rules?.consistency ?? null,
          max_drawdown: newAccount.rules?.maxDrawdown ?? null,
          daily_drawdown: newAccount.rules?.dailyDrawdown ?? null,
          profit_target: newAccount.rules?.profitTarget ?? null,
          winning_days: newAccount.rules?.winningDays ?? null,
          winning_day_threshold: newAccount.rules?.winningDayThreshold ?? null,
        },
      ])
      .select()
      .single()

    if (error) {
      console.error(error)
      showPopup(
        persistentError("Account Creation Failed", "Failed to create account.")
      )
      return
    }

    if (!data) return

    const row: TradeAccountOption = {
      name: data.name,
      size: data.account_size,
      id: data.id,
      account_number: data.account_number ?? null,
      mode: data.mode,
      category: data.category,
      can_add_trades: data.can_add_trades !== false,
    }

    setAccounts((prev) => {
      const next = [...prev, row]
      setCanCreateMoreAccounts(
        isProActive(profile) ||
          countTradeEntryEnabledAccounts(next) < FREE_PLAN_ACCOUNT_LIMIT
      )
      return next
    })
    setSelectedAccount(row)
    setShowCreateModal(false)
    } finally {
      creatingAccountRef.current = false
    }
  }

  if (!open) return null

  const csvAccount =
    selectedAccount != null
      ? {
          id: selectedAccount.id,
          name: selectedAccount.name,
          size: selectedAccount.size,
          mode: selectedAccount.mode,
          category: selectedAccount.category ?? null,
        }
      : null

  return (
    <>
      <FeedbackModal
        {...feedbackModalProps}
        onClose={handleFeedbackClose}
        overlayClassName="z-[1200]"
      />
      <div
      className={`fixed inset-0 z-[1100] flex items-start justify-center overflow-x-hidden px-4 pb-8 pt-[calc(4rem+1rem+6px)] transition-opacity duration-300 motion-reduce:transition-none md:items-center md:py-8 ${
        entered ? "bg-black/75 opacity-100 backdrop-blur-md" : "bg-black/75 opacity-0 backdrop-blur-md"
      }`}
      role="presentation"
    >
      <div
        className={`relative w-full min-w-0 max-w-xl transform transition-all duration-300 ease-out motion-reduce:transition-none motion-reduce:transform-none ${
          entered ? "translate-y-0 scale-100 opacity-100" : "translate-y-3 scale-[0.98] opacity-0"
        }`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="post-setup-import-title"
      >
        <div className={`${MODAL_PANEL_MAX_HEIGHT_CLASS} overflow-x-hidden overflow-y-auto overscroll-contain rounded-2xl border border-white/15 bg-[#0f172a]/95 p-6 shadow-2xl backdrop-blur-xl md:p-8`}>
          <h2
            id="post-setup-import-title"
            className="text-center text-xl font-semibold tracking-tight text-white md:text-2xl"
          >
            Finish Setting Up Your Account
          </h2>
          <p className="mt-2 text-center text-sm text-emerald-200/90">
            Seamlessly import your past trades and start with real data, not a blank slate.
          </p>
          <p className="mt-4 text-center text-sm leading-relaxed text-gray-400">
            Already using another journal? Bring your data with you in seconds.
          </p>

          <p className="mb-2 mt-6 text-xs font-medium uppercase tracking-wide text-gray-400">
            Trading account
          </p>
          <TradeAccountPicker
            accounts={accounts}
            selectedAccount={selectedAccount}
            onSelect={setSelectedAccount}
            onOpenCreate={() => setShowCreateModal(true)}
            disableCreate={!canCreateMoreAccounts}
            hideManageAccounts
          />
          {!selectedAccount ? (
            <p className="mt-2 text-sm text-amber-200/90">
              Please create or select an account before importing trades.
            </p>
          ) : null}

          <ol className="mt-6 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-gray-300">
            <li>Export your trades as a CSV from your current platform</li>
            <li>Upload it here</li>
            <li>We&apos;ll organize everything automatically</li>
          </ol>

          <div className="mt-6 border-t border-white/10 pt-6">
            <p className="mb-4 text-xs font-medium uppercase tracking-wide text-gray-400">
              CSV upload
            </p>
            <CsvImportPanel
              compact
              fileInputId={CSV_INPUT_ID}
              selectedAccount={csvAccount}
              requireSelectedAccount
              delegateSuccessFeedback
              importSource="post_setup_import_modal"
              onImportSuccess={handleImportSuccess}
            />
          </div>

          <div className="mt-6 flex justify-center">
            <button
              type="button"
              onClick={() => void handleSkip()}
              className="rounded-xl border border-white/20 bg-white/5 px-6 py-3 text-sm font-semibold text-gray-200 transition hover:bg-white/10"
            >
              Skip for now
            </button>
          </div>
        </div>
      </div>

      <CreateAccountModal
        open={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSave={(acc) => void handleCreateAccountSave(acc)}
        belowNavbarOnMobile
      />
    </div>
    </>
  )
}
