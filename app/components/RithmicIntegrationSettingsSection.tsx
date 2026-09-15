"use client"

import { useCallback, useEffect, useState } from "react"

type Phase1Meta = {
  enabled: boolean
  phase: number
  scope: string
  productionReady: boolean
}

type DiscoveryResult = {
  ok: boolean
  systemNames: string[]
  selectedSystemName: string | null
  loginSuccess: boolean
  agreementRequired: boolean
  accountCount: number
  accounts: Array<{
    accountName: string | null
    accountCurrency: string | null
    fcmIdMasked: string
    ibIdMasked: string
    accountIdMasked: string
  }>
  diagnostics: string[]
}

export default function RithmicIntegrationSettingsSection() {
  const [meta, setMeta] = useState<Phase1Meta | null>(null)
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<DiscoveryResult | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch("/api/integrations/rithmic/phase1/discovery")
      .then((r) => r.json())
      .then((data) => setMeta(data as Phase1Meta))
      .catch(() => setMeta(null))
  }, [])

  const runDiscovery = useCallback(async (persist: boolean) => {
    setLoading(true)
    setError(null)
    setResult(null)
    try {
      const res = await fetch("/api/integrations/rithmic/phase1/discovery", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ persist }),
      })
      const data = (await res.json()) as DiscoveryResult & { error?: string }
      if (!res.ok) {
        setError(data.error ?? "Discovery failed")
        return
      }
      setResult(data)
    } catch {
      setError("Network error")
    } finally {
      setLoading(false)
    }
  }, [])

  if (meta && !meta.enabled) {
    return null
  }

  return (
    <section className="space-y-4 rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6">
      <div>
        <h2 className="text-lg font-semibold text-white">Rithmic (Test — Phase 1)</h2>
        <p className="mt-1 text-sm text-white/70">
          Development-only connectivity check. Uses TradeTraxs server Test credentials — not
          production-ready Connect. Sign required agreements in R | Trader (Test) before running.
        </p>
      </div>

      <div className="flex flex-wrap gap-3">
        <button
          type="button"
          disabled={loading}
          onClick={() => runDiscovery(false)}
          className="rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white hover:bg-white/15 disabled:opacity-50"
        >
          {loading ? "Running…" : "Run Test discovery"}
        </button>
        <button
          type="button"
          disabled={loading}
          onClick={() => runDiscovery(true)}
          className="rounded-lg border border-white/20 px-4 py-2 text-sm text-white/80 hover:bg-white/5 disabled:opacity-50"
        >
          Run &amp; save accounts
        </button>
      </div>

      {error && <p className="text-sm text-red-300">{error}</p>}

      {result && (
        <div className="space-y-2 rounded-lg border border-white/10 bg-black/20 p-4 text-sm text-white/80">
          <p>
            Status:{" "}
            <span className={result.ok ? "text-emerald-300" : "text-amber-300"}>
              {result.ok ? "OK" : "Incomplete or failed"}
            </span>
          </p>
          {result.agreementRequired && (
            <p className="text-amber-200">
              Agreement may be required — log into Rithmic Test with R | Trader / R | Trader Pro and
              sign pending agreements, then retry.
            </p>
          )}
          <p>System: {result.selectedSystemName ?? "—"}</p>
          <p>Login: {result.loginSuccess ? "success" : "failed"}</p>
          <p>Accounts: {result.accountCount}</p>
          {result.accounts.length > 0 && (
            <ul className="list-inside list-disc">
              {result.accounts.map((a, i) => (
                <li key={i}>
                  {a.accountName ?? "Unnamed"} ({a.accountCurrency ?? "?"}) —{" "}
                  {a.accountIdMasked}
                </li>
              ))}
            </ul>
          )}
          {result.diagnostics.length > 0 && (
            <p className="text-xs text-white/50">Diagnostics: {result.diagnostics.join("; ")}</p>
          )}
        </div>
      )}
    </section>
  )
}
