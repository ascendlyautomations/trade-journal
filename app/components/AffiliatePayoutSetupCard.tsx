"use client"

import { useState } from "react"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import type { AffiliateConnectRow } from "@/lib/affiliateStripeConnect"
import {
  affiliateConnectPhase,
  affiliateConnectPhaseLabel,
  isAffiliatePayoutSetupComplete,
} from "@/lib/affiliateStripeConnect"
import { STRIPE_CONNECT_PRIMARY_BUTTON_CLASS } from "@/lib/affiliateUi"

type Props = {
  /** Affiliate row incl. Stripe Connect fields (null if no row yet). */
  affiliateConnect: AffiliateConnectRow | null
  /** Show this section (e.g. approved affiliate). */
  show: boolean
}

export default function AffiliatePayoutSetupCard({ affiliateConnect, show }: Props) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (!show) return null

  const phase = affiliateConnectPhase(affiliateConnect)
  const phaseLabel = affiliateConnectPhaseLabel(phase)
  const setupComplete = isAffiliatePayoutSetupComplete(affiliateConnect)
  const hasAffiliateRow = Boolean(affiliateConnect?.id)

  async function handleCompleteSetup() {
    setError(null)
    setBusy(true)
    try {
      const res = await fetch("/api/affiliates/connect/account-link", {
        method: "POST",
        credentials: "include",
        headers: {
          ...(await supabaseBearerHeaders()),
        },
      })
      const data = (await res.json().catch(() => ({}))) as { url?: string; error?: string }
      if (!res.ok) {
        setError(typeof data.error === "string" ? data.error : "Could not start onboarding.")
        return
      }
      if (data.url) {
        window.location.href = data.url
        return
      }
      setError("No redirect URL returned.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="rounded-xl border border-white/10 bg-black/20 p-4">
      <p className="text-xs font-medium uppercase tracking-wide text-gray-400">Stripe payout setup</p>
      <p className="mt-2 text-sm text-gray-300">
        Status:{" "}
        <span className="font-semibold text-white">{phaseLabel}</span>
        {setupComplete ? (
          <span className="ml-2 text-emerald-400">· Payouts enabled</span>
        ) : affiliateConnect?.stripe_payouts_enabled === false &&
          affiliateConnect?.stripe_details_submitted ? (
          <span className="ml-2 text-amber-300/90">· Stripe may still be verifying</span>
        ) : null}
      </p>

      {!hasAffiliateRow ? (
        <p className="mt-2 text-xs text-gray-500">
          After your application is approved and your affiliate record is ready, you can complete payout setup
          here.
        </p>
      ) : setupComplete ? (
        <p className="mt-2 text-sm text-emerald-400/95">
          Your payout setup is complete. You can request payouts from the Payouts page when you have a
          balance.
        </p>
      ) : (
        <div className="mt-3 space-y-2">
          <button
            type="button"
            disabled={busy}
            onClick={() => void handleCompleteSetup()}
            className={STRIPE_CONNECT_PRIMARY_BUTTON_CLASS}
          >
            {busy ? "Opening…" : "Complete payout setup"}
          </button>
          {error ? (
            <p className="text-xs text-red-300">{error}</p>
          ) : (
            <p className="text-xs text-gray-500">
              You&apos;ll finish identity and bank details on Stripe&apos;s secure page.
            </p>
          )}
        </div>
      )}
    </div>
  )
}
