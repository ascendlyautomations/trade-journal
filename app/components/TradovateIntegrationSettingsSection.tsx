"use client"

import ActionButton from "@/app/components/ui/ActionButton"
import { startTradovateOAuthConnect } from "@/lib/startTradovateOAuthConnect"
import { supabase } from "@/lib/supabaseClient"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { loadTradingAccounts } from "@/lib/tradingAccounts"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { useCallback, useEffect, useState } from "react"

type TradovateStatus = {
  connected: boolean
  status: string
  connected_at: string | null
  last_sync_at: string | null
  provider_user_id: string | null
  api_environment: string | null
}

type BrokerAccount = {
  id: string
  externalAccountId: string
  externalAccountName: string | null
  tradetraxsAccountId: string | null
  tradetraxsAccountName: string | null
  status: string
}

type AccountsPayload = {
  state: string
  accounts: BrokerAccount[]
}

export default function TradovateIntegrationSettingsSection({
  userId,
}: {
  userId: string | undefined
}) {
  const [status, setStatus] = useState<TradovateStatus | null>(null)
  const [accountsPayload, setAccountsPayload] = useState<AccountsPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [accountsLoading, setAccountsLoading] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [linkTarget, setLinkTarget] = useState<BrokerAccount | null>(null)
  const [ownedAccounts, setOwnedAccounts] = useState<{ id: string; name: string }[]>([])
  const [linkMode, setLinkMode] = useState<"create" | "link">("create")
  const [selectedAccountId, setSelectedAccountId] = useState("")
  const [createSize, setCreateSize] = useState("")

  const loadStatus = useCallback(async () => {
    if (!userId) {
      setStatus(null)
      setLoading(false)
      return
    }
    setLoading(true)
    setError(null)
    try {
      const headers = await supabaseBearerHeaders()
      const res = await fetch("/api/integrations/tradovate/status", { headers })
      if (res.status === 401) {
        setStatus(null)
        return
      }
      if (!res.ok) {
        throw new Error("Could not load Tradovate status.")
      }
      const body = (await res.json()) as TradovateStatus
      setStatus(body)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not load Tradovate status."))
    } finally {
      setLoading(false)
    }
  }, [userId])

  const loadBrokerAccounts = useCallback(
    async (options?: { refresh?: boolean }) => {
      if (!userId) return
      setAccountsLoading(true)
      try {
        const headers = await supabaseBearerHeaders()
        const qs = options?.refresh ? "?refresh=1" : ""
        const res = await fetch(`/api/integrations/tradovate/accounts${qs}`, { headers })
        if (!res.ok) {
          throw new Error("Could not load Tradovate broker accounts.")
        }
        const body = (await res.json()) as AccountsPayload
        setAccountsPayload(body)
      } catch (err) {
        setError(toUserFacingErrorMessage(err, "Could not load Tradovate broker accounts."))
      } finally {
        setAccountsLoading(false)
      }
    },
    [userId]
  )

  useEffect(() => {
    void loadStatus()
  }, [loadStatus])

  const connected = status?.connected === true

  useEffect(() => {
    if (connected && userId) {
      void loadBrokerAccounts()
    } else {
      setAccountsPayload(null)
    }
  }, [connected, userId, loadBrokerAccounts])

  async function handleConnect() {
    setBusy(true)
    setError(null)
    try {
      await startTradovateOAuthConnect()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not connect Tradovate."))
      setBusy(false)
    }
  }

  async function handleDisconnect() {
    setBusy(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch("/api/integrations/tradovate/disconnect", {
        method: "POST",
        headers,
      })
      if (!res.ok) {
        throw new Error("Could not disconnect Tradovate.")
      }
      setAccountsPayload(null)
      await loadStatus()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not disconnect Tradovate."))
    } finally {
      setBusy(false)
    }
  }

  async function openLinkModal(row: BrokerAccount) {
    setLinkTarget(row)
    setLinkMode("create")
    setSelectedAccountId("")
    setCreateSize("")
    if (userId) {
      const { accounts } = await loadTradingAccounts(supabase, userId)
      setOwnedAccounts(accounts.map((a) => ({ id: a.id, name: a.name })))
    }
  }

  async function submitLink() {
    if (!linkTarget) return
    setBusy(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch("/api/integrations/tradovate/accounts/link", {
        method: "POST",
        headers,
        body: JSON.stringify({
          brokerIntegrationAccountId: linkTarget.id,
          action: linkMode,
          tradetraxsAccountId: linkMode === "link" ? selectedAccountId : undefined,
          accountSize: linkMode === "create" ? createSize : undefined,
        }),
      })
      const data = (await res.json()) as { error?: string; accounts?: BrokerAccount[] }
      if (!res.ok) {
        throw new Error(data.error ?? "Could not link account.")
      }
      if (data.accounts) {
        setAccountsPayload((prev) =>
          prev ? { ...prev, accounts: data.accounts! } : { state: "connected", accounts: data.accounts! }
        )
      }
      setLinkTarget(null)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not link account."))
    } finally {
      setBusy(false)
    }
  }

  const accountsState = accountsPayload?.state
  const brokerAccounts = accountsPayload?.accounts ?? []

  return (
    <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
      <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
        Broker integrations
      </h3>
      <p className="mt-1 text-sm text-gray-400">
        Connect supported brokers to import trading activity into TradeTraxs.
      </p>

      <div className="mt-4 rounded-xl border border-white/10 bg-black/20 p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p className="font-medium text-white">Tradovate</p>
            {loading ? (
              <p className="mt-1 text-sm text-gray-400">Checking connection…</p>
            ) : connected ? (
              <p className="mt-1 text-sm text-emerald-300">Connected ✓</p>
            ) : status?.status === "reconnect_required" ? (
              <p className="mt-1 text-sm text-amber-300">Reconnect required</p>
            ) : (
              <p className="mt-1 text-sm text-gray-400">Not connected</p>
            )}
            {connected && status?.api_environment ? (
              <p className="mt-1 text-xs text-gray-500">
                Environment: {status.api_environment}
              </p>
            ) : null}
          </div>
          <div className="flex flex-wrap gap-2">
            {connected ? (
              <>
                <ActionButton
                  type="button"
                  className="rounded-lg border border-white/20 bg-white/10 px-3 py-2 text-sm text-white hover:bg-white/15"
                  disabled={busy || accountsLoading}
                  syncing={accountsLoading}
                  syncingLabel="Refreshing…"
                  onClick={() => void loadBrokerAccounts({ refresh: true })}
                >
                  Refresh Accounts
                </ActionButton>
                <ActionButton
                  type="button"
                  className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/15"
                  disabled={busy || !userId}
                  onClick={() => void handleDisconnect()}
                >
                  Disconnect
                </ActionButton>
              </>
            ) : (
              <ActionButton
                type="button"
                className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
                disabled={busy || loading || !userId}
                onClick={() => void handleConnect()}
              >
                Connect Tradovate
              </ActionButton>
            )}
          </div>
        </div>

        {connected ? (
          <div className="mt-4 border-t border-white/10 pt-4">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
              Broker accounts
            </p>
            {accountsLoading && brokerAccounts.length === 0 ? (
              <p className="mt-2 text-sm text-gray-400">Loading accounts…</p>
            ) : accountsState === "reconnect_required" ? (
              <p className="mt-2 text-sm text-amber-200">
                Tradovate authorization expired. Disconnect and connect again.
              </p>
            ) : accountsState === "provider_unavailable" ? (
              <p className="mt-2 text-sm text-amber-200">
                Tradovate is temporarily unavailable. Try Refresh Accounts later.
              </p>
            ) : brokerAccounts.length === 0 ? (
              <p className="mt-2 text-sm text-gray-400">
                No Tradovate accounts were returned for this login. Try Refresh Accounts.
              </p>
            ) : (
              <ul className="mt-3 space-y-2">
                {brokerAccounts.map((row) => {
                  const label =
                    row.externalAccountName?.trim() ||
                    `Account ${row.externalAccountId}`
                  const linked = Boolean(row.tradetraxsAccountId)
                  return (
                    <li
                      key={row.id}
                      className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-black/30 px-3 py-2"
                    >
                      <div>
                        <p className="text-sm font-medium text-white">{label}</p>
                        <p className="text-xs text-gray-500">ID {row.externalAccountId}</p>
                        {linked ? (
                          <p className="mt-1 text-xs text-emerald-300">
                            Linked → {row.tradetraxsAccountName ?? "Trading account"}
                          </p>
                        ) : (
                          <p className="mt-1 text-xs text-gray-400">Not linked</p>
                        )}
                      </div>
                      <ActionButton
                        type="button"
                        className="rounded-lg border border-blue-400/40 bg-blue-500/10 px-3 py-1.5 text-xs text-blue-200 hover:bg-blue-500/20"
                        disabled={busy}
                        onClick={() => void openLinkModal(row)}
                      >
                        {linked ? "Manage" : "Link Account"}
                      </ActionButton>
                    </li>
                  )
                })}
              </ul>
            )}
          </div>
        ) : null}
      </div>

      {linkTarget ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
          <div className="w-full max-w-md rounded-2xl border border-white/10 bg-[#0f172a] p-5 shadow-xl">
            <h4 className="text-sm font-semibold text-white">Link Tradovate account</h4>
            <p className="mt-1 text-sm text-gray-400">
              {linkTarget.externalAccountName ?? linkTarget.externalAccountId}
            </p>
            <div className="mt-4 flex gap-2">
              <button
                type="button"
                className={`rounded-lg px-3 py-1.5 text-xs ${linkMode === "create" ? "bg-blue-600 text-white" : "bg-white/10 text-gray-300"}`}
                onClick={() => setLinkMode("create")}
              >
                Create New Trading Account
              </button>
              <button
                type="button"
                className={`rounded-lg px-3 py-1.5 text-xs ${linkMode === "link" ? "bg-blue-600 text-white" : "bg-white/10 text-gray-300"}`}
                onClick={() => setLinkMode("link")}
              >
                Link Existing
              </button>
            </div>
            {linkMode === "link" ? (
              <select
                className="mt-4 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
                value={selectedAccountId}
                onChange={(e) => setSelectedAccountId(e.target.value)}
              >
                <option value="">Select trading account…</option>
                {ownedAccounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            ) : (
              <input
                className="mt-4 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
                placeholder="Account value (required if Tradovate did not provide size)"
                value={createSize}
                onChange={(e) => setCreateSize(e.target.value)}
              />
            )}
            <div className="mt-5 flex justify-end gap-2">
              <ActionButton
                type="button"
                className="rounded-lg px-3 py-2 text-sm text-gray-300"
                disabled={busy}
                onClick={() => setLinkTarget(null)}
              >
                Cancel
              </ActionButton>
              <ActionButton
                type="button"
                className="rounded-lg bg-blue-600 px-3 py-2 text-sm text-white"
                disabled={busy}
                syncing={busy}
                syncingLabel="Saving…"
                onClick={() => void submitLink()}
              >
                Save
              </ActionButton>
            </div>
          </div>
        </div>
      ) : null}

      {error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
    </section>
  )
}
