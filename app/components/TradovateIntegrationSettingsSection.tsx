"use client"

import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import ActionButton from "@/app/components/ui/ActionButton"
import { buildTradovateCreateAccountInitialValues } from "@/lib/integrations/tradovate/tradovateBrokerAccountFormDefaults"
import { startTradovateOAuthConnect } from "@/lib/startTradovateOAuthConnect"
import { supabase } from "@/lib/supabaseClient"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { invalidateTradesCache } from "@/lib/appDataCache"
import { ensureAccountsLoaded } from "@/lib/appDataCache"
import { invalidateTradingAccountsSettingsCache } from "@/lib/tradingAccountsSettingsCache"
import { loadTradingAccounts } from "@/lib/tradingAccounts"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import type { TradovateListenerSnapshot } from "@/lib/integrations/tradovate/tradovateListenerStatus"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
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
  externalDisplayName?: string | null
  metadata?: Record<string, unknown>
  tradetraxsAccountId: string | null
  tradetraxsAccountName: string | null
  status: string
  lastSyncSuccessAt?: string | null
  lastSyncStatus?: string
  autoSyncEnabled?: boolean
  lastBrokerEventAt?: string | null
}

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

type ConnectionAccountsPayload = {
  state: string
  accounts: BrokerAccount[]
  listener?: TradovateListenerSnapshot | null
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
  const [creatingAndLinking, setCreatingAndLinking] = useState(false)
  const [syncingMappingId, setSyncingMappingId] = useState<string | null>(null)
  const [syncFeedback, setSyncFeedback] = useState<string | null>(null)

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
    setLinkMode(account.tradetraxsAccountId ? "link" : "create")
    setSelectedAccountId(account.tradetraxsAccountId ?? "")
    if (userId) {
      const { accounts } = await loadTradingAccounts(supabase, userId)
      setOwnedAccounts(accounts.map((a) => ({ id: a.id, name: a.name })))
    }
  }

  async function handleSyncTrades(connectionId: string, account: BrokerAccount) {
    if (!account.tradetraxsAccountId) return
    setSyncingMappingId(account.id)
    setSyncFeedback(null)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch(
        `/api/integrations/tradovate/connections/${connectionId}/accounts/${account.id}/sync`,
        { method: "POST", headers }
      )
      const data = (await res.json()) as {
        error?: string
        summary?: {
          fetched: number
          newExecutions: number
          duplicateExecutions: number
          tradesCreated: number
          tradesUpdated: number
          newTradeIds?: string[]
          status: string
          error?: string
        }
        accounts?: BrokerAccount[]
      }
      if (!res.ok) {
        throw new Error(
          data.summary?.error ?? data.error ?? "Could not sync trades."
        )
      }
      if (data.accounts) {
        setAccountsByConnection((prev) => ({
          ...prev,
          [connectionId]: {
            state: prev[connectionId]?.state ?? "connected",
            accounts: data.accounts!,
          },
        }))
      }
      const s = data.summary
      if (s) {
        const imported = s.tradesCreated
        const updated = s.tradesUpdated
        const dup = s.duplicateExecutions
        setSyncFeedback(
          imported > 0
            ? `${imported} new trade${imported === 1 ? "" : "s"} found${updated > 0 ? ` (${updated} updated)` : ""}.`
            : updated > 0
              ? `Updated ${updated} trade${updated === 1 ? "" : "s"}.`
              : dup > 0 || imported === 0
                ? "You're all caught up — no new Tradovate trades."
                : "Import complete."
        )
      }
      if (userId) {
        invalidateTradesCache(userId)
        invalidateBrokerEnrichmentPendingCount(userId)
        void ensureAccountsLoaded(supabase, userId, { force: true })
      }
      const newIds = s?.newTradeIds ?? []
      if (newIds.length > 0) {
        queueBrokerEnrichment(newIds)
      }
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not sync trades."))
    } finally {
      setSyncingMappingId(null)
    }
  }

  function formatLastSynced(iso: string | null | undefined): string {
    if (!iso) return "Never synced"
    const d = new Date(iso)
    if (Number.isNaN(d.getTime())) return "Never synced"
    return `Last synced: ${d.toLocaleString()}`
  }

  async function applyLinkResponse(
    connectionId: string,
    data: { accounts?: BrokerAccount[] }
  ) {
    if (data.accounts) {
      setAccountsByConnection((prev) => ({
        ...prev,
        [connectionId]: {
          state: "connected",
          accounts: data.accounts!,
        },
      }))
    }
    if (userId) {
      invalidateTradingAccountsSettingsCache(userId)
      void ensureAccountsLoaded(supabase, userId, { force: true })
    }
  }

  async function submitLinkExisting() {
    if (!linkTarget || linkMode !== "link") return
    if (!selectedAccountId) {
      setError("Select a TradeTraxs account.")
      return
    }
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
            action: "link",
            tradetraxsAccountId: selectedAccountId,
          }),
        }
      )
      const data = (await res.json()) as { error?: string; accounts?: BrokerAccount[] }
      if (!res.ok) {
        throw new Error(data.error ?? "Could not link account.")
      }
      await applyLinkResponse(linkTarget.connectionId, data)
      setLinkTarget(null)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not link account."))
    } finally {
      setBusy(false)
    }
  }

  async function submitCreateAndLink(newAccount: CreateAccountSavePayload) {
    if (!linkTarget || creatingAndLinking) return
    setCreatingAndLinking(true)
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
            action: "create",
            createAccount: {
              name: newAccount.name,
              size: newAccount.size,
              accountNumber: newAccount.id,
              category: newAccount.category,
              mode: newAccount.mode,
              rules: newAccount.rules,
            },
          }),
        }
      )
      const data = (await res.json()) as { error?: string; accounts?: BrokerAccount[] }
      if (!res.ok) {
        throw new Error(data.error ?? "Could not create and link account.")
      }
      await applyLinkResponse(linkTarget.connectionId, data)
      setLinkTarget(null)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not create and link account."))
      throw err
    } finally {
      setCreatingAndLinking(false)
    }
  }

  const brokerCreateInitial = linkTarget
    ? buildTradovateCreateAccountInitialValues({
        externalAccountId: linkTarget.account.externalAccountId,
        externalAccountName: linkTarget.account.externalAccountName,
        metadata: linkTarget.account.metadata,
      })
    : null

  const brokerDisplayName =
    linkTarget?.account.externalAccountName ??
    linkTarget?.account.externalDisplayName ??
    linkTarget?.account.externalAccountId ??
    ""

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
                                  <>
                                    <p className="text-xs text-emerald-300">
                                      Linked → {row.tradetraxsAccountName ?? "Trading account"}
                                    </p>
                                    <p className="text-xs text-gray-500">
                                      {formatLastSynced(row.lastSyncSuccessAt)}
                                    </p>
                                  </>
                                ) : (
                                  <p className="text-xs text-gray-400">Not linked</p>
                                )}
                              </div>
                              <div className="flex flex-wrap items-center gap-2">
                                {linked ? (
                                  <ActionButton
                                    type="button"
                                    className="rounded-lg border border-emerald-400/40 bg-emerald-500/10 px-3 py-1.5 text-xs text-emerald-200"
                                    disabled={busy || syncingMappingId === row.id}
                                    onClick={() => void handleSyncTrades(connection.id, row)}
                                  >
                                    {syncingMappingId === row.id ? "Importing…" : "Import new trades"}
                                  </ActionButton>
                                ) : null}
                                <ActionButton
                                  type="button"
                                  className="rounded-lg border border-blue-400/40 bg-blue-500/10 px-3 py-1.5 text-xs text-blue-200"
                                  disabled={busy}
                                  onClick={() => void openLinkModal(connection.id, row)}
                                >
                                  {linked ? "Manage" : "Link Account"}
                                </ActionButton>
                              </div>
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

      {syncFeedback ? (
        <p className="text-sm text-emerald-200/90">{syncFeedback}</p>
      ) : null}

      {linkTarget && linkMode === "create" && brokerCreateInitial ? (
        <CreateAccountModal
          open
          dialogTitle="Create & link trading account"
          dialogSubtitle="Set up your TradeTraxs account, then we will link this Tradovate account."
          saveLabel="Create & link"
          overlayClassName="z-[100]"
          initialAccount={brokerCreateInitial}
          brokerContext={{
            brokerName: "Tradovate",
            brokerAccountName: brokerDisplayName,
            brokerAccountId: linkTarget.account.externalAccountId,
          }}
          supplementaryFooterLink={{
            label: "Link an existing TradeTraxs account instead",
            onClick: () => setLinkMode("link"),
            disabled: creatingAndLinking,
          }}
          onClose={() => setLinkTarget(null)}
          onSave={async (acc) => {
            await submitCreateAndLink(acc)
          }}
        />
      ) : null}

      {linkTarget && linkMode === "link" ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4">
          <div className="w-full max-w-md rounded-2xl border border-white/10 bg-[#0f172a] p-5 shadow-xl">
            <h4 className="text-sm font-semibold text-white">Link Tradovate account</h4>
            <p className="mt-1 text-sm text-gray-400">{brokerDisplayName}</p>
            <div className="mt-4 flex gap-2">
              <button
                type="button"
                className="rounded-lg bg-white/10 px-3 py-1.5 text-xs text-gray-300"
                onClick={() => setLinkMode("create")}
              >
                Create new trading account
              </button>
              <button
                type="button"
                className="rounded-lg bg-blue-600 px-3 py-1.5 text-xs text-white"
              >
                Link existing
              </button>
            </div>
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
                disabled={busy || !selectedAccountId}
                syncing={busy}
                syncingLabel="Linking…"
                onClick={() => void submitLinkExisting()}
              >
                Link account
              </ActionButton>
            </div>
          </div>
        </div>
      ) : null}

      {error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
    </section>
  )
}
