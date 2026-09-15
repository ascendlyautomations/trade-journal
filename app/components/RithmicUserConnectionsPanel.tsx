"use client"

import { useCallback, useEffect, useState } from "react"
import ActionButton from "@/app/components/ui/ActionButton"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

type ConnectMeta = {
  userConnectEnabled: boolean
  showConnectUi: boolean
  apiEnvironment: string
  credentialModelStatus: string
  productionUserAuthConfirmed: boolean
}

type RithmicConnection = {
  id: string
  label: string
  connected: boolean
  status: string
  api_environment: string | null
}

export default function RithmicUserConnectionsPanel({
  userId,
  onConnectionsChanged,
}: {
  userId: string | undefined
  onConnectionsChanged?: () => void
}) {
  const [meta, setMeta] = useState<ConnectMeta | null>(null)
  const [connections, setConnections] = useState<RithmicConnection[]>([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showForm, setShowForm] = useState(false)
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [systemName, setSystemName] = useState("")
  const [systemChoices, setSystemChoices] = useState<string[]>([])
  const [reconnectId, setReconnectId] = useState<string | null>(null)

  const clearSecrets = useCallback(() => {
    setPassword("")
  }, [])

  const loadConnections = useCallback(async () => {
    if (!userId) {
      setConnections([])
      return
    }
    const headers = await supabaseBearerHeaders()
    const res = await fetch("/api/integrations/rithmic/connections", { headers })
    if (!res.ok) return
    const body = (await res.json()) as { connections: RithmicConnection[] }
    setConnections(body.connections ?? [])
  }, [userId])

  const refresh = useCallback(async () => {
    if (!userId) {
      setLoading(false)
      return
    }
    setLoading(true)
    try {
      const headers = await supabaseBearerHeaders()
      const [metaRes] = await Promise.all([
        fetch("/api/integrations/rithmic/connect", { headers }),
        loadConnections(),
      ])
      if (metaRes.ok) {
        setMeta((await metaRes.json()) as ConnectMeta)
      }
    } finally {
      setLoading(false)
    }
  }, [userId, loadConnections])

  useEffect(() => {
    void refresh()
  }, [refresh])

  if (!userId || loading) return null
  if (!meta?.showConnectUi) return null

  async function submitConnect() {
    if (!userId) return
    setBusy(true)
    setError(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch("/api/integrations/rithmic/connect", {
        method: "POST",
        headers,
        body: JSON.stringify({
          username: username.trim(),
          password,
          systemName: systemName.trim() || undefined,
          reconnectConnectionId: reconnectId ?? undefined,
        }),
      })
      const data = (await res.json()) as {
        ok?: boolean
        code?: string
        userMessage?: string
        systemNames?: string[]
        connectionId?: string
      }
      clearSecrets()

      if (data.code === "system_selection_required" && data.systemNames?.length) {
        setSystemChoices(data.systemNames)
        setShowForm(true)
        setError(null)
        return
      }

      if (!res.ok || !data.ok) {
        throw new Error(data.userMessage ?? "Could not connect Rithmic.")
      }

      setShowForm(false)
      setSystemChoices([])
      setSystemName("")
      setUsername("")
      setReconnectId(null)
      await loadConnections()
      onConnectionsChanged?.()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not connect Rithmic."))
    } finally {
      setBusy(false)
      clearSecrets()
    }
  }

  async function disconnect(connectionId: string) {
    setBusy(true)
    setError(null)
    try {
      const headers = await supabaseBearerHeaders()
      const res = await fetch(
        `/api/integrations/rithmic/connections/${connectionId}/disconnect`,
        { method: "POST", headers }
      )
      if (!res.ok) throw new Error("Could not disconnect.")
      await loadConnections()
      onConnectionsChanged?.()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not disconnect Rithmic."))
    } finally {
      setBusy(false)
    }
  }

  function openReconnect(connection: RithmicConnection) {
    setReconnectId(connection.id)
    setShowForm(true)
    setSystemChoices([])
    setSystemName("")
    clearSecrets()
  }

  return (
    <div className="mt-6 space-y-4 border-t border-white/10 pt-6">
      <div>
        <h3 className="text-base font-semibold text-white">Connect Rithmic</h3>
        <p className="mt-1 text-sm text-white/60">
          Sign in with your Rithmic credentials. Password is sent once over HTTPS, encrypted on
          our servers, and never stored in your browser.
          {meta.apiEnvironment === "test" ? (
            <span className="block mt-1 text-amber-200/80">
              Test environment only — do not use production trading passwords until Rithmic
              confirms third-party access.
            </span>
          ) : null}
        </p>
      </div>

      {error ? <p className="text-sm text-red-300">{error}</p> : null}

      <div className="flex flex-wrap gap-3">
        <ActionButton
          type="button"
          className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
          disabled={busy}
          onClick={() => {
            setReconnectId(null)
            setShowForm(true)
          }}
        >
          {connections.length > 0 ? "+ Connect Another Rithmic Account" : "Connect Rithmic"}
        </ActionButton>
      </div>

      {connections.length > 0 ? (
        <ul className="space-y-2">
          {connections.map((c) => (
            <li
              key={c.id}
              className="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-white/10 bg-black/30 px-3 py-2"
            >
              <div>
                <p className="text-sm text-white">{c.label}</p>
                <p className="text-xs text-gray-500">
                  {c.status === "connected"
                    ? "Connected"
                    : c.status === "reconnect_required"
                      ? "Reconnect required"
                      : c.status}
                  {c.api_environment ? ` · ${c.api_environment}` : null}
                </p>
              </div>
              <div className="flex gap-2">
                {c.status === "reconnect_required" ? (
                  <ActionButton
                    type="button"
                    className="rounded-lg border border-amber-400/40 px-3 py-1.5 text-xs text-amber-100"
                    disabled={busy}
                    onClick={() => openReconnect(c)}
                  >
                    Reconnect
                  </ActionButton>
                ) : null}
                <ActionButton
                  type="button"
                  className="rounded-lg border border-white/20 px-3 py-1.5 text-xs text-white/80"
                  disabled={busy}
                  onClick={() => void disconnect(c.id)}
                >
                  Disconnect
                </ActionButton>
              </div>
            </li>
          ))}
        </ul>
      ) : null}

      {showForm ? (
        <div className="rounded-xl border border-white/10 bg-black/25 p-4">
          <h4 className="text-sm font-medium text-white">
            {reconnectId ? "Reconnect Rithmic" : "Connect Rithmic"}
          </h4>
          <div className="mt-3 space-y-3">
            <label className="block">
              <span className="text-xs text-gray-400">Rithmic username</span>
              <input
                type="text"
                autoComplete="username"
                className="mt-1 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
              />
            </label>
            <label className="block">
              <span className="text-xs text-gray-400">Rithmic password</span>
              <input
                type="password"
                autoComplete="current-password"
                className="mt-1 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </label>
            {systemChoices.length > 0 ? (
              <label className="block">
                <span className="text-xs text-gray-400">Rithmic system</span>
                <select
                  className="mt-1 w-full rounded-lg border border-white/15 bg-black/40 px-3 py-2 text-sm text-white"
                  value={systemName}
                  onChange={(e) => setSystemName(e.target.value)}
                >
                  <option value="">Select system…</option>
                  {systemChoices.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}
          </div>
          <div className="mt-4 flex justify-end gap-2">
            <button
              type="button"
              className="rounded-lg px-3 py-2 text-sm text-gray-400"
              onClick={() => {
                setShowForm(false)
                clearSecrets()
                setReconnectId(null)
              }}
            >
              Cancel
            </button>
            <ActionButton
              type="button"
              className="rounded-lg bg-blue-600 px-4 py-2 text-sm text-white"
              disabled={busy || !username.trim() || !password}
              onClick={() => void submitConnect()}
            >
              {busy ? "Verifying…" : "Connect"}
            </ActionButton>
          </div>
        </div>
      ) : null}
    </div>
  )
}
