"use client"

import { useCallback, useEffect, useState } from "react"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

type EnvPresence = {
  phase1ApiEnabled: boolean
  apiEnvSet: boolean
  apiEnvIsTest: boolean
  apiUserSet: boolean
  apiPasswordSet: boolean
}

type RuntimeAssets = {
  protoBundlePresent: boolean
  sslCaPresent: boolean
  missingProtoCount: number
}

type Phase1Meta = {
  enabled: boolean
  phase: number
  scope: string
  productionReady: boolean
  envPresence?: EnvPresence
  runtimeAssets?: RuntimeAssets
}

type DiscoveryResult = {
  ok: boolean
  userMessage?: string
  lastSuccessfulStage?: string
  failureStage?: string | null
  loginAttempted?: boolean
  runtimeAssets?: RuntimeAssets
  systemNames: string[]
  selectedSystemName: string | null
  loginSuccess: boolean
  loginRpCode?: string[]
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
  stagesCompleted?: string[]
}

type ApiErrorBody = {
  error?: string
  code?: string
  userMessage?: string
  envPresence?: EnvPresence
  runtimeAssets?: RuntimeAssets
  lastSuccessfulStage?: string
  failureStage?: string | null
  detail?: string
}

function resolveApiErrorMessage(data: ApiErrorBody, status: number): string {
  if (data.userMessage?.trim()) return data.userMessage.trim()
  if (data.error?.trim()) return data.error.trim()
  if (status === 401) {
    return "Your TradeTraxs session expired. Please sign in again."
  }
  if (data.detail) return data.detail
  return "Discovery failed."
}

export default function RithmicIntegrationSettingsSection() {
  const [meta, setMeta] = useState<Phase1Meta | null>(null)
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<DiscoveryResult | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    void (async () => {
      try {
        const headers = await supabaseBearerHeaders()
        const res = await fetch("/api/integrations/rithmic/phase1/discovery", { headers })
        const data = (await res.json()) as Phase1Meta
        setMeta(data)
      } catch {
        setMeta(null)
      }
    })()
  }, [])

  const runDiscovery = useCallback(async (persist: boolean) => {
    setLoading(true)
    setError(null)
    setResult(null)
    try {
      const headers = {
        ...(await supabaseBearerHeaders()),
        "Content-Type": "application/json",
      }
      const res = await fetch("/api/integrations/rithmic/phase1/discovery", {
        method: "POST",
        headers,
        body: JSON.stringify({ persist }),
      })
      const data = (await res.json()) as DiscoveryResult & ApiErrorBody
      if (!res.ok) {
        setError(resolveApiErrorMessage(data, res.status))
        if (data.runtimeAssets || data.lastSuccessfulStage) {
          setResult({
            ok: false,
            systemNames: [],
            selectedSystemName: null,
            loginSuccess: false,
            agreementRequired: false,
            accountCount: 0,
            accounts: [],
            diagnostics: data.detail ? [data.detail] : [],
            userMessage: resolveApiErrorMessage(data, res.status),
            lastSuccessfulStage: data.lastSuccessfulStage,
            failureStage: data.failureStage,
            runtimeAssets: data.runtimeAssets,
          })
        }
        return
      }
      setResult(data)
      if (data.userMessage) {
        setError(data.ok ? null : data.userMessage)
      } else if (!data.ok) {
        setError("Rithmic discovery did not complete.")
      }
    } catch {
      setError("Network error")
    } finally {
      setLoading(false)
    }
  }, [])

  if (meta && !meta.enabled) {
    return null
  }

  const env = meta?.envPresence
  const envOk =
    env?.phase1ApiEnabled && env.apiEnvIsTest && env.apiUserSet && env.apiPasswordSet
  const assetsOk =
    meta?.runtimeAssets?.protoBundlePresent !== false &&
    meta?.runtimeAssets?.sslCaPresent !== false

  return (
    <section className="space-y-4 rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6">
      <div>
        <h2 className="text-lg font-semibold text-white">Rithmic (Test — Phase 1)</h2>
        <p className="mt-1 text-sm text-white/70">
          Development-only connectivity check. Uses TradeTraxs server Test credentials — not
          production-ready Connect. Sign required agreements in R | Trader (Test) before running.
        </p>
        {meta?.envPresence && (
          <p className="mt-2 text-xs text-white/50">
            Server env (presence): phase1={String(env?.phase1ApiEnabled)} test=
            {String(env?.apiEnvIsTest)} user={String(env?.apiUserSet)} password=
            {String(env?.apiPasswordSet)}
            {meta.runtimeAssets
              ? ` · protos=${String(meta.runtimeAssets.protoBundlePresent)} ca=${String(meta.runtimeAssets.sslCaPresent)}`
              : null}
          </p>
        )}
        {meta?.envPresence && !envOk ? (
          <p className="mt-2 text-sm text-amber-200/90">
            Server Rithmic Test configuration looks incomplete. Confirm Vercel env vars and redeploy.
          </p>
        ) : null}
        {meta?.runtimeAssets && !assetsOk ? (
          <p className="mt-2 text-sm text-amber-200/90">
            Rithmic protocol or TLS files may be missing from the deployment bundle.
          </p>
        ) : null}
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
          {result.userMessage ? (
            <p className={result.ok ? "text-emerald-300" : "text-amber-200"}>{result.userMessage}</p>
          ) : null}
          <p>
            Status:{" "}
            <span className={result.ok ? "text-emerald-300" : "text-amber-300"}>
              {result.ok ? "OK" : "Incomplete or failed"}
            </span>
          </p>
          {result.lastSuccessfulStage ? (
            <p className="text-xs text-white/55">
              Last successful stage: {result.lastSuccessfulStage}
              {result.failureStage ? ` · Failed at: ${result.failureStage}` : null}
            </p>
          ) : null}
          {result.loginAttempted === false && result.failureStage ? (
            <p className="text-xs text-white/55">Rithmic login was not attempted.</p>
          ) : null}
          {result.systemNames.length > 0 && (
            <p className="text-xs text-white/60">
              Systems: {result.systemNames.join(", ")}
            </p>
          )}
          <p>System selected: {result.selectedSystemName ?? "—"}</p>
          <p>Login: {result.loginSuccess ? "success" : result.loginAttempted ? "failed" : "not attempted"}</p>
          {result.loginRpCode && result.loginRpCode.length > 0 && !result.loginSuccess ? (
            <p className="text-xs text-white/55">Login rp_code: {result.loginRpCode.join(" · ")}</p>
          ) : null}
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
