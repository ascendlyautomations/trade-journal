"use client"

import ActionButton from "@/app/components/ui/ActionButton"
import { startTradovateOAuthConnect } from "@/lib/startTradovateOAuthConnect"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
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

export default function TradovateIntegrationSettingsSection({
  userId,
}: {
  userId: string | undefined
}) {
  const [status, setStatus] = useState<TradovateStatus | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

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

  useEffect(() => {
    void loadStatus()
  }, [loadStatus])

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
      await loadStatus()
    } catch (err) {
      setError(toUserFacingErrorMessage(err, "Could not disconnect Tradovate."))
    } finally {
      setBusy(false)
    }
  }

  const connected = status?.connected === true

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
            ) : (
              <p className="mt-1 text-sm text-gray-400">Not connected</p>
            )}
            {connected && status?.api_environment ? (
              <p className="mt-1 text-xs text-gray-500">
                Environment: {status.api_environment}
              </p>
            ) : null}
          </div>
          <div>
            {connected ? (
              <ActionButton
                type="button"
                className="rounded-lg border border-white/20 bg-white/10 px-4 py-2 text-sm text-white hover:bg-white/15"
                disabled={busy || !userId}
                onClick={() => void handleDisconnect()}
              >
                Disconnect
              </ActionButton>
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
      </div>

      {error ? <p className="mt-3 text-sm text-red-300">{error}</p> : null}
    </section>
  )
}
