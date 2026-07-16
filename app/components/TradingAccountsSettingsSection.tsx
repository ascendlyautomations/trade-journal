"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import { FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import { feedbackPresets } from "@/lib/feedbackPresets"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureAccountsLoaded,
  getCachedAccounts,
  invalidateAccountsCache,
  subscribeAppDataCache,
} from "@/lib/appDataCache"
import {
  assertCanCreateTradingAccount,
  formatTradingAccountMode,
  FREE_PLAN_ACCOUNT_LIMIT,
  FREE_PLAN_ACCOUNT_LIMIT_MESSAGE,
  insertTradingAccount,
  mapTradingAccountRow,
  setTradingAccountActive,
  tradingAccountDisplayTitle,
  tradingAccountToFormValues,
  updateTradingAccount,
  updateTradingAccountNote,
  matchesTradingAccountSearch,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"
import { countTradeEntryEnabledAccounts } from "@/lib/freePlanAccountSlots"

const ACCOUNTS_PAGE_SIZE = 5

function mapCachedAccountRows(rows: any[]): TradingAccountListItem[] {
  return rows.map((row) =>
    mapTradingAccountRow(row as Record<string, unknown>)
  )
}

function sortAccountsForDisplay(
  accounts: TradingAccountListItem[]
): TradingAccountListItem[] {
  return [...accounts].sort((a, b) => {
    if (a.is_active !== b.is_active) return a.is_active ? -1 : 1
    return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
  })
}

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
  const [loading, setLoading] = useState(Boolean(userId))
  const [togglingId, setTogglingId] = useState<string | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [creating, setCreating] = useState(false)
  const [editModalAccount, setEditModalAccount] =
    useState<TradingAccountListItem | null>(null)
  const [savingEdit, setSavingEdit] = useState(false)
  const [searchQuery, setSearchQuery] = useState("")
  const [page, setPage] = useState(0)
  const [noteEditingAccount, setNoteEditingAccount] =
    useState<TradingAccountListItem | null>(null)
  const [savingNoteId, setSavingNoteId] = useState<string | null>(null)

  const canCreateMore = isPro
    ? true
    : countTradeEntryEnabledAccounts(accounts) < FREE_PLAN_ACCOUNT_LIMIT

  const editFormValues = useMemo(
    () =>
      editModalAccount ? tradingAccountToFormValues(editModalAccount) : null,
    [editModalAccount]
  )

  const filteredAccounts = useMemo(() => {
    const sorted = sortAccountsForDisplay(accounts)
    const q = searchQuery.trim()
    if (!q) return sorted
    return sorted.filter((account) => matchesTradingAccountSearch(account, q))
  }, [accounts, searchQuery])

  const pageCount = Math.max(1, Math.ceil(filteredAccounts.length / ACCOUNTS_PAGE_SIZE))
  const safePage = Math.min(page, pageCount - 1)
  const pageStart = safePage * ACCOUNTS_PAGE_SIZE
  const paginatedAccounts = filteredAccounts.slice(
    pageStart,
    pageStart + ACCOUNTS_PAGE_SIZE
  )
  const rangeStart = filteredAccounts.length === 0 ? 0 : pageStart + 1
  const rangeEnd = Math.min(pageStart + ACCOUNTS_PAGE_SIZE, filteredAccounts.length)

  useEffect(() => {
    setPage(0)
  }, [searchQuery])

  const refreshAccounts = useCallback(
    async (options?: { force?: boolean }) => {
      if (!userId) return

      const cached = getCachedAccounts(userId)
      if (cached && !options?.force) {
        setAccounts(mapCachedAccountRows(cached))
        setLoading(false)
        return
      }

      if (!cached) setLoading(true)
      try {
        const rows = await ensureAccountsLoaded(supabase, userId, options)
        setAccounts(mapCachedAccountRows(rows))
      } catch (error) {
        console.error(error)
        showPopup({ type: "error", message: handleSupabaseError(error) })
      } finally {
        setLoading(false)
      }
    },
    [userId, showPopup]
  )

  function invalidateAccountCaches() {
    if (!userId) return
    invalidateAccountsCache(userId)
  }

  useEffect(() => {
    if (!userId) {
      setAccounts([])
      setLoading(false)
      return
    }

    const cached = getCachedAccounts(userId)
    if (cached) {
      setAccounts(mapCachedAccountRows(cached))
      setLoading(false)
    }

    void refreshAccounts({ force: true })

    return subscribeAppDataCache(() => {
      const next = getCachedAccounts(userId)
      if (next) setAccounts(mapCachedAccountRows(next))
    })
  }, [userId, refreshAccounts])

  async function handleToggleActive(account: TradingAccountListItem) {
    if (!userId || togglingId) return
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
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    setAccounts((prev) =>
      prev.map((a) =>
        a.id === account.id ? { ...a, is_active: nextActive } : a
      )
    )
    invalidateAccountCaches()
    void refreshAccounts({ force: true })
    showPopup({
      type: "success",
      message: nextActive ? "Account activated" : "Account deactivated",
    })
  }

  async function handleCreateAccountSave(newAccount: CreateAccountSavePayload) {
    if (!userId || creating) return

    setCreating(true)
    const { data: profile } = await supabase
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", userId)
      .maybeSingle()

    const gate = await assertCanCreateTradingAccount(supabase, userId, profile)
    if (!gate.ok) {
      setCreating(false)
      showPopup(feedbackPresets.accountLimit())
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
      showPopup({
        type: "error",
        message:
          error.message === "An account with this name already exists"
            ? error.message
            : handleSupabaseError(error),
      })
      return
    }

    if (!account) return

    setAccounts((prev) => [...prev, account])
    setShowCreateModal(false)
    invalidateAccountCaches()
    void refreshAccounts({ force: true })
    showPopup({ type: "success", message: "Account created" })
  }

  function openNoteEditor(account: TradingAccountListItem) {
    setNoteEditingAccount({ ...account, note: account.note ?? "" })
  }

  async function handleEditAccountSave(newAccount: CreateAccountSavePayload) {
    if (!userId || !editModalAccount || savingEdit) return

    setSavingEdit(true)
    const { account, error } = await updateTradingAccount(
      supabase,
      userId,
      editModalAccount.id,
      newAccount,
      editModalAccount
    )
    setSavingEdit(false)

    if (error) {
      console.error(error)
      showPopup({
        type: "error",
        message:
          error.message === "An account with this name already exists"
            ? error.message
            : handleSupabaseError(error),
      })
      return
    }

    if (!account) return

    setEditModalAccount(null)
    showPopup({ type: "success", message: "Account updated" })
    invalidateAccountCaches()
    await refreshAccounts({ force: true })
  }

  async function saveNote(account: TradingAccountListItem) {
    if (savingNoteId) return
    const noteVal = account.note ?? ""
    setSavingNoteId(account.id)
    const { error } = await updateTradingAccountNote(
      supabase,
      account.id,
      noteVal
    )
    setSavingNoteId(null)

    if (error) {
      console.error(error)
      showPopup({ type: "error", message: handleSupabaseError(error) })
      return
    }

    setAccounts((prev) =>
      prev.map((a) =>
        a.id === account.id ? { ...a, note: noteVal } : a
      )
    )
    setNoteEditingAccount(null)
    invalidateAccountCaches()
    void refreshAccounts({ force: true })
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
          <p className="mt-4 text-sm text-gray-400">Loading accounts…</p>
        ) : accounts.length === 0 ? (
          <p className="mt-4 text-sm text-gray-400">No accounts yet.</p>
        ) : (
          <>
            <label className="mt-4 block">
              <span className="sr-only">Search accounts</span>
              <input
                type="search"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search accounts..."
                className="w-full rounded-xl border border-white/10 bg-black/30 p-3 text-sm text-white placeholder:text-gray-400"
              />
            </label>

            {filteredAccounts.length === 0 ? (
              <p className="mt-4 text-sm text-gray-400">
                No accounts match your search.
              </p>
            ) : (
              <>
                <ul className="mt-4 space-y-3">
                  {paginatedAccounts.map((account) => {
                    const modeLabel = formatTradingAccountMode(account.mode)
                    const isActive = account.is_active
                    const busy = togglingId === account.id
                    const isEditingNote =
                      noteEditingAccount?.id === account.id
                    const noteText = account.note?.trim() ?? ""
                    const savingNote = savingNoteId === account.id

                    return (
                      <li
                        key={account.id}
                        className="rounded-xl border border-white/10 bg-black/20 p-4"
                      >
                        <p className="flex flex-wrap items-baseline gap-x-1 font-medium text-white">
                          <span>{tradingAccountDisplayTitle(account)}</span>
                          {account.account_number?.trim() ? (
                            <span className="text-sm font-normal text-gray-400">
                              · ID: {account.account_number.trim()}
                            </span>
                          ) : null}
                        </p>
                        <dl className="mt-2 space-y-1 text-sm text-gray-400">
                          <div className="flex gap-2">
                            <dt className="shrink-0 text-gray-400">Category:</dt>
                            <dd>{account.category || "Personal"}</dd>
                          </div>
                          {modeLabel ? (
                            <div className="flex gap-2">
                              <dt className="shrink-0 text-gray-400">Mode:</dt>
                              <dd>{modeLabel}</dd>
                            </div>
                          ) : null}
                          <div className="flex gap-2">
                            <dt className="shrink-0 text-gray-400">Status:</dt>
                            <dd
                              className={
                                isActive ? "text-emerald-300" : "text-red-300/90"
                              }
                            >
                              {isActive ? "Active" : "Inactive"}
                            </dd>
                          </div>
                        </dl>

                        {isEditingNote ? (
                          <div className="mt-3 space-y-2 rounded-lg border border-white/10 bg-white/[0.04] p-3">
                            <input
                              value={noteEditingAccount.note ?? ""}
                              onChange={(e) =>
                                setNoteEditingAccount({
                                  ...noteEditingAccount,
                                  note: e.target.value,
                                })
                              }
                              placeholder="Note (e.g. blown, passed...)"
                              className="w-full rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-sm text-white placeholder:text-gray-400"
                            />
                            <div className="flex flex-wrap items-center gap-3">
                              <button
                                type="button"
                                disabled={savingNote}
                                onClick={() => void saveNote(noteEditingAccount)}
                                className="text-sm font-medium text-blue-400 hover:text-blue-300 disabled:opacity-50"
                              >
                                {savingNote ? "Saving…" : "Save"}
                              </button>
                              <button
                                type="button"
                                disabled={savingNote}
                                onClick={() => setNoteEditingAccount(null)}
                                className="text-sm text-gray-400 hover:text-gray-300 disabled:opacity-50"
                              >
                                Cancel
                              </button>
                            </div>
                          </div>
                        ) : (
                          <>
                            {noteText ? (
                              <div className="mt-3 text-sm text-gray-400">
                                <span className="text-gray-400">Note:</span>
                                <p className="mt-1 whitespace-pre-wrap text-gray-300">
                                  {noteText}
                                </p>
                              </div>
                            ) : null}
                            <div className="mt-3 flex flex-wrap gap-2">
                              <button
                                type="button"
                                onClick={() => setEditModalAccount(account)}
                                className="rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-emerald-300 transition hover:bg-white/10"
                              >
                                Edit
                              </button>
                              <button
                                type="button"
                                onClick={() => openNoteEditor(account)}
                                className="rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-xs font-medium text-blue-300 transition hover:bg-white/10"
                              >
                                {noteText ? "Edit Note" : "Add Note"}
                              </button>
                              <button
                                type="button"
                                disabled={busy}
                                onClick={() => void handleToggleActive(account)}
                                className={`rounded-lg px-3 py-1.5 text-xs font-medium transition disabled:opacity-50 ${
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
                            </div>
                          </>
                        )}
                      </li>
                    )
                  })}
                </ul>

                <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <p className="text-sm text-gray-400">
                    Showing {rangeStart}–{rangeEnd} of {filteredAccounts.length}
                    <span className="text-gray-400">
                      {" "}
                      · Page {safePage + 1} of {pageCount}
                    </span>
                  </p>
                  <div className="flex gap-2">
                    <button
                      type="button"
                      onClick={() => setPage((p) => Math.max(0, p - 1))}
                      disabled={safePage === 0}
                      className="rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Previous
                    </button>
                    <button
                      type="button"
                      onClick={() =>
                        setPage((p) => Math.min(pageCount - 1, p + 1))
                      }
                      disabled={safePage >= pageCount - 1}
                      className="rounded-lg border border-white/10 bg-white/5 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      Next
                    </button>
                  </div>
                </div>
              </>
            )}
          </>
        )}

        <div className="mt-4">
          {canCreateMore ? (
            <button
              type="button"
              onClick={() => setShowCreateModal(true)}
              disabled={creating || !userId}
              className="rounded-xl border border-blue-500/40 bg-blue-500/15 px-4 py-2.5 text-sm font-medium text-blue-200 transition hover:bg-blue-500/25 disabled:opacity-50"
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
      <CreateAccountModal
        open={editModalAccount != null}
        initialAccount={editFormValues}
        onClose={() => setEditModalAccount(null)}
        onSave={(acc) => void handleEditAccountSave(acc)}
      />
      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
