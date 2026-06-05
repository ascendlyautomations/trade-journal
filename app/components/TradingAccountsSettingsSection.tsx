"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { supabase } from "@/lib/supabaseClient"
import { isProActive } from "@/lib/subscription"
import {
  assertCanCreateTradingAccount,
  formatTradingAccountMode,
  FREE_PLAN_ACCOUNT_LIMIT_MESSAGE,
  insertTradingAccount,
  loadTradingAccounts,
  setTradingAccountActive,
  sortTradingAccountsForManagement,
  tradingAccountDisplayTitle,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

type Props = {
  userId: string | undefined
  isPro: boolean
}

export default function TradingAccountsSettingsSection({
  userId,
  isPro,
}: Props) {
  const { showPopup, feedbackModalProps } = useFeedbackPopup()
  const [accounts, setAccounts] = useState<TradingAccountListItem[]>([])
  const [loading, setLoading] = useState(false)
  const [togglingId, setTogglingId] = useState<string | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [creating, setCreating] = useState(false)

  const canCreateMore = isPro || accounts.length < 1

  const sortedAccounts = useMemo(
    () => sortTradingAccountsForManagement(accounts),
    [accounts]
  )

  const refreshAccounts = useCallback(async () => {
    if (!userId) return
    setLoading(true)
    const { accounts: loaded, error } = await loadTradingAccounts(
      supabase,
      userId
    )
    setLoading(false)
    if (error) {
      console.error(error)
      showPopup({ type: "error", message: "Something went wrong" })
      return
    }
    setAccounts(loaded)
  }, [userId, showPopup])

  useEffect(() => {
    void refreshAccounts()
  }, [refreshAccounts])

  async function handleToggleActive(account: TradingAccountListItem) {
    if (!userId) return
    const nextActive = !account.is_active
    setTogglingId(account.id)
    const { error } = await setTradingAccountActive(
      supabase,
      account.id,
      nextActive
    )
    setTogglingId(null)

    if (error) {
      console.error(error)
      showPopup({ type: "error", message: "Something went wrong" })
      return
    }

    setAccounts((prev) =>
      prev.map((a) =>
        a.id === account.id ? { ...a, is_active: nextActive } : a
      )
    )
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    if (!userId) return

    setCreating(true)
    const { data: profile } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", userId)
      .maybeSingle()

    const gate = await assertCanCreateTradingAccount(supabase, userId, profile)
    if (!gate.ok) {
      setCreating(false)
      showPopup({ type: "error", message: gate.message })
      return
    }

    const { account, error } = await insertTradingAccount(
      supabase,
      userId,
      newAccount
    )
    setCreating(false)

    if (error) {
      console.error(error)
      showPopup({ type: "error", message: "Something went wrong" })
      return
    }

    if (!account) return

    setAccounts((prev) => [...prev, account])
    setShowCreateModal(false)
    showPopup({ type: "success", message: "Account created" })
  }

  return (
    <>
      <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
          Trading Accounts
        </h3>
        <p className="mt-1 text-sm text-gray-400">
          Manage which accounts appear in trade logging. Inactive accounts stay
          linked to existing trades but are hidden from the account picker.
        </p>

        {loading && accounts.length === 0 ? (
          <p className="mt-4 text-sm text-gray-500">Loading accounts…</p>
        ) : accounts.length === 0 ? (
          <p className="mt-4 text-sm text-gray-500">No accounts yet.</p>
        ) : (
          <ul className="mt-4 space-y-3">
            {sortedAccounts.map((account) => {
              const modeLabel = formatTradingAccountMode(account.mode)
              const isActive = account.is_active
              const busy = togglingId === account.id

              return (
                <li
                  key={account.id}
                  className="rounded-xl border border-white/10 bg-black/20 p-4"
                >
                  <p className="font-medium text-white">
                    {tradingAccountDisplayTitle(account)}
                  </p>
                  <dl className="mt-2 space-y-1 text-sm text-gray-400">
                    <div className="flex gap-2">
                      <dt className="shrink-0 text-gray-500">Category:</dt>
                      <dd>{account.category || "Personal"}</dd>
                    </div>
                    {modeLabel ? (
                      <div className="flex gap-2">
                        <dt className="shrink-0 text-gray-500">Mode:</dt>
                        <dd>{modeLabel}</dd>
                      </div>
                    ) : null}
                    <div className="flex gap-2">
                      <dt className="shrink-0 text-gray-500">Status:</dt>
                      <dd
                        className={
                          isActive ? "text-emerald-300" : "text-red-300/90"
                        }
                      >
                        {isActive ? "Active" : "Inactive"}
                      </dd>
                    </div>
                  </dl>
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => void handleToggleActive(account)}
                    className={`mt-3 rounded-lg px-3 py-1.5 text-xs font-medium transition disabled:opacity-50 ${
                      isActive
                        ? "bg-red-500/15 text-red-200 hover:bg-red-500/25"
                        : "bg-emerald-500/15 text-emerald-200 hover:bg-emerald-500/25"
                    }`}
                  >
                    {busy
                      ? "Updating…"
                      : isActive
                        ? "Deactivate Account"
                        : "Activate Account"}
                  </button>
                </li>
              )
            })}
          </ul>
        )}

        <div className="mt-4">
          {canCreateMore ? (
            <button
              type="button"
              onClick={() => setShowCreateModal(true)}
              disabled={creating || !userId}
              className="rounded-xl border border-emerald-500/40 bg-emerald-500/15 px-4 py-2.5 text-sm font-medium text-emerald-200 transition hover:bg-emerald-500/25 disabled:opacity-50"
            >
              + Add Account
            </button>
          ) : (
            <p className="text-sm text-amber-200/90">
              {FREE_PLAN_ACCOUNT_LIMIT_MESSAGE}
            </p>
          )}
        </div>
      </section>

      <CreateAccountModal
        open={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSave={(acc) => void handleCreateAccountSave(acc)}
      />
      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
