"use client"

import { useEffect, useState } from "react"
import CsvImportPanel from "@/app/components/CsvImportPanel"
import TradeAccountPicker, {
  type TradeAccountOption,
} from "@/app/components/TradeAccountPicker"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import { supabase } from "@/lib/supabaseClient"
import { isProActive } from "@/lib/subscription"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets, persistentError } from "@/lib/feedbackPresets"

const CSV_INPUT_ID = "post-setup-csv-import"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

type Props = {
  open: boolean
  onComplete: () => void | Promise<void>
}

export default function PostSetupImportModal({ open, onComplete }: Props) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [entered, setEntered] = useState(false)
  const [accounts, setAccounts] = useState<TradeAccountOption[]>([])
  const [selectedAccount, setSelectedAccount] = useState<TradeAccountOption | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [canCreateMoreAccounts, setCanCreateMoreAccounts] = useState(true)

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
      const {
        data: { user },
      } = await supabase.auth.getUser()
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
      }))

      setAccounts(formatted)

      const { data: profile } = await supabase
        .from("profiles")
        .select("is_pro, subscription_status")
        .eq("id", user.id)
        .maybeSingle()
      const userIsPro = isProActive(profile)
      setCanCreateMoreAccounts(userIsPro || formatted.length < 1)
    }

    void loadAccounts()
  }, [open])

  async function handleSkip() {
    await onComplete()
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return

    const { data: profile } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .maybeSingle()
    const userIsPro = isProActive(profile)
    if (!userIsPro) {
      const { data: existingAccounts, error: countErr } = await supabase
        .from("accounts")
        .select("id")
        .eq("user_id", user.id)
      if (countErr) {
        console.error(countErr)
        showPopup(
          persistentError(
            "Could Not Verify Limit",
            "Failed to verify account limit."
          )
        )
        return
      }
      if ((existingAccounts || []).length >= 1) {
        setCanCreateMoreAccounts(false)
        showPopup(feedbackPresets.accountLimit())
        return
      }
    }

    const { data, error } = await supabase
      .from("accounts")
      .insert([
        {
          user_id: user.id,
          name: newAccount.name,
          account_size: newAccount.size,
          account_number: newAccount.id,
          category: newAccount.category,
          mode: newAccount.mode,
          consistency: newAccount.rules?.consistency ?? null,
          max_drawdown: newAccount.rules?.maxDrawdown ?? null,
          daily_drawdown: newAccount.rules?.dailyDrawdown ?? null,
          profit_target: newAccount.rules?.profitTarget ?? null,
          winning_days: newAccount.rules?.winningDays ?? null,
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
    }

    setAccounts((prev) => [...prev, row])
    setSelectedAccount(row)
    setCanCreateMoreAccounts(isProActive(profile))
    setShowCreateModal(false)
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
      <FeedbackModal {...feedbackModalProps} />
      <div
      className={`fixed inset-0 z-[1100] flex items-center justify-center overflow-x-hidden px-4 py-8 transition-opacity duration-300 motion-reduce:transition-none ${
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
        <div className="max-h-[min(90vh,760px)] overflow-x-hidden overflow-y-auto rounded-2xl border border-white/15 bg-[#0f172a]/95 p-6 shadow-2xl backdrop-blur-xl md:p-8">
          <h2
            id="post-setup-import-title"
            className="text-center text-xl font-semibold tracking-tight text-white md:text-2xl"
          >
            Finish Setting Up Your Account
          </h2>
          <p className="mt-2 text-center text-sm text-emerald-200/90">
            Seamlessly import your past trades and start with real data — not a blank slate.
          </p>
          <p className="mt-4 text-center text-sm leading-relaxed text-gray-400">
            Already using another journal? Bring your data with you in seconds.
          </p>

          <p className="mb-2 mt-6 text-xs font-medium uppercase tracking-wide text-gray-500">
            Trading account
          </p>
          <TradeAccountPicker
            accounts={accounts}
            selectedAccount={selectedAccount}
            onSelect={setSelectedAccount}
            onOpenCreate={() => setShowCreateModal(true)}
            disableCreate={!canCreateMoreAccounts}
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
            <p className="mb-4 text-xs font-medium uppercase tracking-wide text-gray-500">
              CSV upload
            </p>
            <CsvImportPanel
              compact
              fileInputId={CSV_INPUT_ID}
              selectedAccount={csvAccount}
              requireSelectedAccount
              onImportSuccess={() => void onComplete()}
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
      />
    </div>
    </>
  )
}
