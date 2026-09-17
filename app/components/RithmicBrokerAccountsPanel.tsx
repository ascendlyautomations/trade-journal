"use client"

import CreateAccountModal, {
  type Props as CreateAccountModalProps,
} from "@/components/CreateAccountModal"
import ActionButton from "@/app/components/ui/ActionButton"
import { buildRithmicCreateAccountInitialValues } from "@/lib/integrations/rithmic/rithmicBrokerAccountFormDefaults"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { invalidateTradesCache } from "@/lib/appDataCache"
import { ensureAccountsLoaded } from "@/lib/appDataCache"
import { invalidateTradingAccountsSettingsCache } from "@/lib/tradingAccountsSettingsCache"
import { loadTradingAccounts } from "@/lib/tradingAccounts"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
import { useCallback, useEffect, useMemo, useState } from "react"

type RithmicConnection = {
  id: string
  label: string
  connected: boolean
  status: string
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
}

type CreateAccountSavePayload = Parameters<CreateAccountModalProps["onSave"]>[0]

function formatLastSynced(iso: string | null | undefined): string {
  if (!iso) return "Never imported"
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return "Never imported"
  return `Last imported ${d.toLocaleString()}`
}

export default function RithmicBrokerAccountsPanel({
  userId,
  onDiscoveryPersist,
}: {
  userId: string | undefined
  onDiscoveryPersist?: () => void
}) {
  const [connections, setConnections] = useState<RithmicConnection[]>([])
  const [accountsByConnection, setAccountsByConnection] = useState<
    Record<string, { state: string; accounts: BrokerAccount[] }>
  >({})
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [syncingMappingId, setSyncingMappingId] = useState<string | null>(null)
  const [syncFeedback, setSyncFeedback] = useState<string | null>(null)
  const [importPasswordPrompt, setImportPasswordPrompt] = useState<{
    connectionId: string
    account: BrokerAccount
  } | null>(null)
  const [importPassword, setImportPassword] = useState("")
  const [linkTarget, setLinkTarget] = useState<{
    connectionId: string
    account: BrokerAccount
  } | null>(null)
  const [linkMode, setLinkMode] = useState<"create" | "link">("create")
  const [ownedAccounts, setOwnedAccounts] = useState<{ id: string; name: string }[]>([])
  const [selectedAccountId, setSelectedAccountId] = useState("")
  const [creatingAndLinking, setCreatingAndLinking] = useState(false)

  const loadConnectionAccounts = useCallback(async (connectionId: string) => {
    const headers = await supabaseBearerHeaders()
    const res = await fetch(
      `/api/integrations/rithmic/connections/${connectionId}/accounts`,
      { headers }
    )
    if (!res.ok) throw new Error("Could not load Rithmic accounts.")
    const body = (await res.json()) as { state: string; accounts: BrokerAccount[] }
    setAccountsByConnection((prev) => ({ ...prev, [connectionId]: body }))
  }, [])

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
      const res = await fetch("/api/integrations/rithmic/connections", { headers })
      if (res.status === 401) {
        setConnections([])
        return
      }
      if (!res.ok) throw new Error("Could not load Rithmic connections.")
      const body = (await res.json()) as { connections: RithmicConnection[] }
      const list = body.connections ?? []
      setConnections(list)
      await Promise.all(
        list.filter((c) => c.connected).map((c) => loadConnectionAccounts(c.id))
      )
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not load Rithmic connections."))
    } finally {
      setLoading(false)
    }
  }, [userId, loadConnectionAccounts])

  useEffect(() => {
    void loadConnections()
  }, [loadConnections])

  const brokerCreateInitial = useMemo(() => {
    if (!linkTarget) return null
    const view = {
      id: linkTarget.account.id,
      provider: "rithmic" as const,
      externalAccountId: linkTarget.account.externalAccountId,
      externalAccountName: linkTarget.account.externalAccountName,
      externalDisplayName: linkTarget.account.externalDisplayName ?? null,
      metadata: linkTarget.account.metadata ?? {},
      tradetraxsAccountId: linkTarget.account.tradetraxsAccountId,
      tradetraxsAccountName: linkTarget.account.tradetraxsAccountName,
      syncEnabled: true,
      status: "discovered" as const,
      discoveredAt: "",
      lastSeenAt: "",
    }
    return buildRithmicCreateAccountInitialValues(view)
  }, [linkTarget])

  const brokerDisplayName =
    linkTarget?.account.externalAccountName?.trim() ||
    linkTarget?.account.externalAccountId ||
    "Rithmic account"

  async function openLinkModal(connectionId: string, account: BrokerAccount) {
    setLinkTarget({ connectionId, account })
    setLinkMode(account.tradetraxsAccountId ? "link" : "create")
    setSelectedAccountId(account.tradetraxsAccountId ?? "")
    if (userId) {
      const { accounts } = await loadTradingAccounts(supabase, userId)
      setOwnedAccounts(accounts.map((a) => ({ id: a.id, name: a.name })))
    }
  }

  async function submitCreateAndLink(acc: CreateAccountSavePayload) {
    if (!linkTarget || !userId) return
    setCreatingAndLinking(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch(
        `/api/integrations/rithmic/connections/${linkTarget.connectionId}/accounts/link`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({
            brokerIntegrationAccountId: linkTarget.account.id,
            action: "create",
            createAccount: {
              name: acc.name,
              size: acc.size,
              accountNumber: acc.id,
              category: acc.category,
              mode: acc.mode,
              rules: acc.rules,
            },
          }),
        }
      )
      const data = (await res.json()) as { error?: string; accounts?: BrokerAccount[] }
      if (!res.ok) throw new Error(data.error ?? "Could not link account.")
      if (data.accounts) {
        setAccountsByConnection((prev) => ({
          ...prev,
          [linkTarget.connectionId]: {
            state: prev[linkTarget.connectionId]?.state ?? "connected",
            accounts: data.accounts!,
          },
        }))
      }
      invalidateTradingAccountsSettingsCache(userId)
      await ensureAccountsLoaded(supabase, userId, { force: true })
      setLinkTarget(null)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not create and link account."))
    } finally {
      setCreatingAndLinking(false)
    }
  }

  async function submitLinkExisting() {
    if (!linkTarget || !userId || !selectedAccountId) return
    setBusy(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch(
        `/api/integrations/rithmic/connections/${linkTarget.connectionId}/accounts/link`,
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
      if (!res.ok) throw new Error(data.error ?? "Could not link account.")
      if (data.accounts) {
        setAccountsByConnection((prev) => ({
          ...prev,
          [linkTarget.connectionId]: {
            state: prev[linkTarget.connectionId]?.state ?? "connected",
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

  async function handleSyncTrades(
    connectionId: string,
    account: BrokerAccount,
    transientPassword?: string | null
  ) {
    if (!account.tradetraxsAccountId || !userId) return
    setSyncingMappingId(account.id)
    setSyncFeedback(null)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch(
        `/api/integrations/rithmic/connections/${connectionId}/accounts/${account.id}/sync`,
        {
          method: "POST",
          headers,
          body: JSON.stringify(
            transientPassword
              ? { password: transientPassword }
              : {}
          ),
        }
      )
      const data = (await res.json()) as {
        error?: string
        summary?: {
          tradesCreated: number
          tradesUpdated: number
          duplicateExecutions: number
          newTradeIds?: string[]
          error?: string
          errorCode?: string
        }
        accounts?: BrokerAccount[]
      }
      if (
        !res.ok &&
        data.summary?.errorCode === "rithmic_password_required"
      ) {
        setImportPasswordPrompt({ connectionId, account })
        setImportPassword("")
        setError(
          data.summary.error ??
            "Enter your Rithmic password to import. TradeTraxs does not save it."
        )
        return
      }
      if (!res.ok) {
        throw new Error(data.summary?.error ?? data.error ?? "Could not import trades.")
      }
      setImportPasswordPrompt(null)
      setImportPassword("")
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
      const newIds = s?.newTradeIds ?? []
      if (s) {
        const imported = s.tradesCreated
        setSyncFeedback(
          imported > 0
            ? `${imported} new trade${imported === 1 ? "" : "s"} imported.`
            : "You're all caught up — no new Rithmic trades."
        )
      }
      invalidateTradesCache(userId)
      invalidateBrokerEnrichmentPendingCount(userId)
      if (newIds.length > 0) queueBrokerEnrichment(newIds)
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not import Rithmic trades."))
    } finally {
      setSyncingMappingId(null)
    }
  }

  if (!userId) return null
  if (loading && connections.length === 0) {
    return <p className="text-sm text-white/60">Loading saved Rithmic accounts…</p>
  }
  if (connections.length === 0) {
    return (
      <p className="text-sm text-white/60">
        Run &amp; save accounts above to create a Rithmic Test connection, then link and import
        trades here.
      </p>
    )
  }

  return (
    <div className="mt-6 space-y-4 border-t border-white/10 pt-6">
      <div>
        <h3 className="text-base font-semibold text-white">Phase 2 — Manual import</h3>
        <p className="mt-1 text-sm text-white/60">
          Link discovered accounts, then import fill history on demand. No background sync.
        </p>
      </div>

      {error ? <p className="text-sm text-red-300">{error}</p> : null}
      {syncFeedback ? <p className="text-sm text-emerald-200/90">{syncFeedback}</p> : null}

      {importPasswordPrompt ? (
        <div className="rounded-xl border border-amber-400/30 bg-amber-950/20 p-4">
          <h4 className="text-sm font-medium text-white">
            Enter Rithmic password to import
          </h4>
          <p className="mt-1 text-xs text-white/60">
            Password is sent once over HTTPS for this import and is not stored.
          </p>
          <label className="mt-3 block">
            <span className="text-xs text-gray-400">Rithmic password</span>
            <input
              type="password"
              autoComplete="current-password"
              className="mt-1 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
              value={importPassword}
              onChange={(e) => setImportPassword(e.target.value)}
            />
          </label>
          <div className="mt-3 flex justify-end gap-2">
            <button
              type="button"
              className="rounded-lg px-3 py-2 text-sm text-gray-400"
              onClick={() => {
                setImportPasswordPrompt(null)
                setImportPassword("")
              }}
            >
              Cancel
            </button>
            <ActionButton
              type="button"
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm text-white"
              disabled={
                !importPassword ||
                syncingMappingId === importPasswordPrompt.account.id
              }
              onClick={() =>
                void handleSyncTrades(
                  importPasswordPrompt.connectionId,
                  importPasswordPrompt.account,
                  importPassword
                )
              }
            >
              {syncingMappingId === importPasswordPrompt.account.id
                ? "Importing…"
                : "Import"}
            </ActionButton>
          </div>
        </div>
      ) : null}

      {connections.map((connection) => {
        const payload = accountsByConnection[connection.id]
        const brokerAccounts = payload?.accounts ?? []

        return (
          <div
            key={connection.id}
            className="rounded-xl border border-white/10 bg-black/20 p-4"
          >
            <p className="font-medium text-white">{connection.label}</p>
            <p className="mt-1 text-xs text-gray-500">
              {connection.api_environment ?? "test"} · {connection.status}
            </p>
            <ActionButton
              type="button"
              className="mt-3 rounded-lg border border-white/20 bg-white/10 px-3 py-1.5 text-xs text-white"
              disabled={busy}
              onClick={() => {
                void onDiscoveryPersist?.()
                void loadConnectionAccounts(connection.id)
              }}
            >
              Refresh account list
            </ActionButton>

            {!payload ? (
              <p className="mt-3 text-sm text-gray-400">Loading accounts…</p>
            ) : brokerAccounts.length === 0 ? (
              <p className="mt-3 text-sm text-gray-400">
                No saved accounts. Run &amp; save accounts in Phase 1.
              </p>
            ) : (
              <ul className="mt-3 space-y-2">
                {brokerAccounts.map((row) => {
                  const label =
                    row.externalAccountName?.trim() || row.externalAccountId.split("|").pop()
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
                              Rithmic → {row.tradetraxsAccountName ?? "Trading account"}
                            </p>
                            <p className="text-xs text-gray-500">
                              {formatLastSynced(row.lastSyncSuccessAt)}
                            </p>
                          </>
                        ) : (
                          <p className="text-xs text-gray-400">Not linked</p>
                        )}
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {linked ? (
                          <ActionButton
                            type="button"
                            className="rounded-lg border border-emerald-400/40 bg-emerald-500/10 px-3 py-1.5 text-xs text-emerald-200"
                            disabled={busy || syncingMappingId === row.id}
                            onClick={() => void handleSyncTrades(connection.id, row)}
                          >
                            {syncingMappingId === row.id ? "Importing…" : "Import New Trades"}
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
        )
      })}

      {linkTarget && linkMode === "create" && brokerCreateInitial ? (
        <CreateAccountModal
          open
          dialogTitle="Create & link trading account"
          dialogSubtitle="Rithmic provides account name and ID; choose prop firm, size, and other journal fields."
          saveLabel="Create & link"
          overlayClassName="z-[100]"
          initialAccount={brokerCreateInitial}
          brokerContext={{
            brokerName: "Rithmic",
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
            <h4 className="text-sm font-semibold text-white">Link Rithmic account</h4>
            <p className="mt-1 text-sm text-gray-400">{brokerDisplayName}</p>
            <select
              className="mt-4 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white"
              value={selectedAccountId}
              onChange={(e) => setSelectedAccountId(e.target.value)}
            >
              <option value="">Select account…</option>
              {ownedAccounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                className="rounded-lg px-3 py-2 text-sm text-gray-400"
                onClick={() => setLinkTarget(null)}
              >
                Cancel
              </button>
              <button
                type="button"
                className="rounded-lg bg-blue-600 px-3 py-2 text-sm text-white disabled:opacity-50"
                disabled={!selectedAccountId || busy}
                onClick={() => void submitLinkExisting()}
              >
                Link
              </button>
            </div>
            <button
              type="button"
              className="mt-3 text-xs text-blue-300"
              onClick={() => setLinkMode("create")}
            >
              Create new TradeTraxs account instead
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
