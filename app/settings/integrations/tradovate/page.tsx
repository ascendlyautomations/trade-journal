"use client"

import Link from "next/link"
import { useSearchParams } from "next/navigation"
import { Suspense, useMemo } from "react"
import {
  tradovateCallbackUserMessage,
  type TradovateCallbackOutcome,
} from "@/lib/integrations/tradovate/tradovateOAuthCallback"

function TradovateIntegrationResultInner() {
  const searchParams = useSearchParams()

  const message = useMemo(() => {
    const status = searchParams.get("status")
    if (status === "success") {
      return tradovateCallbackUserMessage({ kind: "success" })
    }
    if (status === "error") {
      const reason = searchParams.get("reason")
      const allowed = [
        "denied",
        "invalid_state",
        "missing_code",
        "state_expired",
        "token_exchange",
        "identity_mismatch",
        "server",
      ] as const
      const normalized = allowed.includes(reason as (typeof allowed)[number])
        ? (reason as Extract<TradovateCallbackOutcome, { kind: "error" }>["reason"])
        : "server"
      return tradovateCallbackUserMessage({ kind: "error", reason: normalized })
    }
    return "Connect Tradovate from TradeTraxs settings when broker linking is available."
  }, [searchParams])

  const isSuccess = searchParams.get("status") === "success"

  return (
    <div className="flex min-h-[50vh] flex-col items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-6 py-16 text-center text-white">
      <h1 className="mb-3 text-xl font-semibold tracking-tight">
        {isSuccess ? "Tradovate" : "Connection issue"}
      </h1>
      <p className="max-w-md text-sm leading-relaxed text-gray-300">{message}</p>
      <Link
        href="/settings"
        className="mt-8 inline-flex rounded-lg bg-white/10 px-4 py-2 text-sm font-medium text-white ring-1 ring-white/20 transition hover:bg-white/15"
      >
        Back to Settings
      </Link>
    </div>
  )
}

export default function TradovateIntegrationResultPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-[50vh] items-center justify-center bg-[#0f172a] text-sm text-gray-400">
          Loading…
        </div>
      }
    >
      <TradovateIntegrationResultInner />
    </Suspense>
  )
}
