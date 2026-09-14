"use client"

import ActionButton from "@/app/components/ui/ActionButton"
import { startTradovateOAuthConnect } from "@/lib/startTradovateOAuthConnect"
import { supabase } from "@/lib/supabaseClient"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { loadTradingAccounts } from "@/lib/tradingAccounts"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { useCallback, useEffect, useState } from "react"

type TradovateConnection = {
  id: string
  label: string
  connected: boolean
  status: string
  provider_display_name: string | null
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

type ConnectionAccountsPayload = {
  state: string
  accounts: BrokerAccount[]
}

export default function TradovateIntegrationSettingsSection({
  userId,
}: {
  userId: string | undefined
}) {
  const [connections, setConnections] = useState<TradovateConnection[]>([])
  const [accountsByConnection, setAccountsByConnection] = useState<
    Record<string, ConnectionAccountsPayload>
  >({})
  const [loading, setLoading] = useState(true)
  const [refreshingId, setRefreshingId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [linkTarget, setLinkTarget] = useState<{
    connectionId: string
    account: BrokerAccount
  } | null>(null)
  const [ownedAccounts, setOwnedAccounts] = useState<{ id: string; name: string }[]>([])
  const [linkMode, setLinkMode] = useState<"create" | "link">("create")
  const [selectedAccountId, setSelectedAccountId] = useState("")
  const [createSize, setCreateSize] = useState("")

  const loadConnectionAccounts = useCallback(
    async (connectionId: string, refresh?: boolean) => {
      const headers = await supabaseBearerHeaders()
      const qs = refresh ? "?refresh=1" : ""
      const res = await fetch(
        `/api/integrations/tradovate/connections/${connectionId}/accounts${qs}`,
        { headers }
      )
      if (!res.ok) {
        throw new Error("Could not load broker accounts for this connection.")
      }
      const body = (await res.json()) as ConnectionAccountsPayload
      setAccountsByConnection((prev) => ({ ...prev, [connectionId]: body }))
    },
    []
  )

  const loadConnections = useCallback(async () => {
    if (!userId) {
      setConnections([])
      setLoading(false)
      return
    }
    setLoading(true)
    setError(null)
    try {
      const headers = await supabaseBearerHeaders()
      const res = await fetch("/api/integrations/tradovate/connections", { headers })
      if (res.status === 401) {
        setConnections([])
        return
      }
      if (!res.ok) throw new Error("Could not load Tradovate connections.")
      const body = (await res.json()) as { connections: TradovateConnection[] }
      const list = body.connections ?? []
      setConnections(list)
      await Promise.all(
        list.filter((c) => c.connected).map((c) => loadConnectionAccounts(c.id))
      )
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not load Tradovate connections."))
    } finally {
      setLoading(false)
    }
  }, [userId, loadConnectionAccounts])

  useEffect(() => {
    void loadConnections()
  }, [loadConnections])

  async function handleConnect(reconnectConnectionId?: string) {
    setBusy(true)
    setError(null)
    try {
      await startTradovateOAuthConnect(
        reconnectConnectionId ? { reconnectConnectionId } : undefined
      )
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not connect Tradovate."))
      setBusy(false)
    }
  }

  async function handleDisconnect(connectionId: string) {
    setBusy(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch(
        `/api/integrations/tradovate/connections/${connectionId}/disconnect`,
        { method: "POST", headers }
      )
      if (!res.ok) throw new Error("Could not disconnect this Tradovate connection.")
      await loadConnections()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not disconnect Tradovate."))
    } finally {
      setBusy(false)
    }
  }

  async function handleRefreshAccounts(connectionId: string) {
    setRefreshingId(connectionId)
    setError(null)
    try {
      const headers = await supabaseBearerHeaders()
      const res = await fetch(
        `/api/integrations/tradovate/connections/${connectionId}/accounts/refresh`,
        { method: "POST", headers }
      )
      if (!res.ok) throw new Error("Could not refresh accounts.")
      const body = (await res.json()) as ConnectionAccountsPayload & { connectionId: string }
      setAccountsByConnection((prev) => ({
        ...prev,
        [connectionId]: { state: body.state, accounts: body.accounts },
      }))
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not refresh accounts."))
    } finally {
      setRefreshingId(null)
    }
  }

  async function openLinkModal(connectionId: string, account: BrokerAccount) {
    setLinkTarget({ connectionId, account })
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
      const res = await fetch(
        `/api/integrations/tradovate/connections/${linkTarget.connectionId}/accounts/link`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({
            brokerIntegrationAccountId: linkTarget.account.id,
            action: linkMode,
            tradetraxsAccountId: linkMode === "link" ? selectedAccountId : undefined,
            accountSize: linkMode === "create" ? createSize : undefined,
          }),
        }
      )
      const data = (await res.json()) as { error?: string; accounts?: BrokerAccount[] }
      if (!res.ok) {
        throw new Error(data.error ?? "Could not link account.")
      }
      if (data.accounts) {
        setAccountsByConnection((prev) => ({
          ...prev,
          [linkTarget.connectionId]: {
            state: "connected",
            accounts: data.accounts!,
          },
        }))
      }
      setLinkTarget(null)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not link account."))
    } finally {
      setBusy(false)
    }
  }

  const connectionCount = connections.length
  const hasConnections = connectionCount > 0

  return (
    <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
            Broker integrations
          </h3>
          <p className="mt-1 text-sm font-medium text-white">
            Tradovate
            {hasConnections ? (
              <span className="ml-2 text-sm font-normal text-gray-400">
                {connectionCount} connection{connectionCount === 1 ? "" : "s"}
              </span>
            ) : null}
          </p>
          {!hasConnections && !loading ? (
            <p className="mt-2 text-sm text-gray-400">
              Connect your Tradovate accounts to automatically sync trading data.
            </p>
          ) : null}
        </div>
        {!loading ? (
          <ActionButton
            type="button"
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
            disabled={busy || !userId}
            onClick={() => void handleConnect()}
          >
            {hasConnections ? "+ Connect Another Tradovate Account" : "Connect Tradovate"}
          </ActionButton>
        ) : null}
      </div>

      {loading ? (
        <p className="mt-4 text-sm text-gray-400">Loading connections…</p>
      ) : (
        <div className="mt-4 space-y-4">
          {connections.map((connection) => {
            const payload = accountsByConnection[connection.id]
            const brokerAccounts = payload?.accounts ?? []
            const accountsState = payload?.state
            const isConnected = connection.connected

            return (
              <div
                key={connection.id}
                className="rounded-xl border border-white/10 bg-black/20 p-4"
              >
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <p className="font-medium text-white">{connection.label}</p>
                    {isConnected ? (
                      <p className="mt-1 text-sm text-emerald-300">Connected ✓</p>
                    ) : connection.status === "reconnect_required" ? (
                      <p className="mt-1 text-sm text-amber-300">Reconnect required</p>
                    ) : (
                      <p className="mt-1 text-sm text-gray-400">{connection.status}</p>
                    )}
                    {connection.api_environment ? (
                      <p className="mt-1 text-xs text-gray-500">
                        Environment: {connection.api_environment}
                      </p>
                    ) : null}
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {connection.status === "reconnect_required" ? (
                      <ActionButton
                        type="button"
                        className="rounded-lg border border-amber-400/40 bg-amber-500/10 px-3 py-2 text-xs text-amber-100"
                        disabled={busy}
                        onClick={() => void handleConnect(connection.id)}
                      >
                        Reconnect
                      </ActionButton>
                    ) : null}
                    {isConnected ? (
                      <ActionButton
                        type="button"
                        className="rounded-lg border border-white/20 bg-white/10 px-3 py-2 text-xs text-white"
                        disabled={busy || refreshingId === connection.id}
                        syncing={refreshingId === connection.id}
                        syncingLabel="Refreshing…"
                        onClick={() => void handleRefreshAccounts(connection.id)}
                      >
                        Refresh Accounts
                      </ActionButton>
                    ) : null}
                    <ActionButton
                      type="button"
                      className="rounded-lg border border-white/20 bg-white/10 px-3 py-2 text-xs text-white"
                      disabled={busy}
                      onClick={() => void handleDisconnect(connection.id)}
                    >
                      Disconnect
                    </ActionButton>
                  </div>
                </div>

                {isConnected ? (
                  <div className="mt-4 border-t border-white/10 pt-3">
                    <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                      Broker accounts
                    </p>
                    {accountsState === "reconnect_required" ? (
                      <p className="mt-2 text-sm text-amber-200">
                        Authorization expired for this connection. Reconnect to continue.
                      </p>
                    ) : !payload ? (
                      <p className="mt-2 text-sm text-gray-400">Loading accounts…</p>
                    ) : brokerAccounts.length === 0 ? (
                      <p className="mt-2 text-sm text-gray-400">
                        No accounts returned. Try Refresh Accounts.
                      </p>
                    ) : (
                      <ul className="mt-2 space-y-2">
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
                                <p className="text-sm text-white">{label}</p>
                                {linked ? (
                                  <p className="text-xs text-emerald-300">
                                    Linked → {row.tradetraxsAccountName ?? "Trading account"}
                                  </p>
                                ) : (
                                  <p className="text-xs text-gray-400">Not linked</p>
                                )}
                              </div>
                              <ActionButton
                                type="button"
                                className="rounded-lg border border-blue-400/40 bg-blue-500/10 px-3 py-1.5 text-xs text-blue-200"
                                disabled={busy}
                                onClick={() => void openLinkModal(connection.id, row)}
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
            )
          })}
        </div>
      )}

      {linkTarget ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
          <div className="w-full max-w-md rounded-2xl border border-white/10 bg-[#0f172a] p-5 shadow-xl">
            <h4 className="text-sm font-semibold text-white">Link Tradovate account</h4>
            <p className="mt-1 text-sm text-gray-400">
              {linkTarget.account.externalAccountName ?? linkTarget.account.externalAccountId}
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
