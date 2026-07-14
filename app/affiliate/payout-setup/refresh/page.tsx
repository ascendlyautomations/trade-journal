"use client"

import Link from "next/link"

export default function AffiliatePayoutSetupRefreshPage() {
  return (
    <>
      <div className="mx-auto max-w-lg px-4 py-16 text-center text-white">
        <div className="rounded-xl border border-amber-500/35 bg-amber-500/10 px-6 py-8">
          <h1 className="text-lg font-semibold text-amber-100">Onboarding link expired</h1>
          <p className="mt-2 text-sm text-amber-100/90">
            Stripe could not resume the previous session. Go back and tap{" "}
            <strong className="text-white">Complete payout setup</strong> again, from your affiliate
            dashboard, settings (Affiliate tab), or payouts page.
          </p>
          <div className="mt-6 flex flex-wrap justify-center gap-3">
            <Link
              href="/payouts"
              className="inline-block rounded-lg bg-blue-500 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-blue-600"
            >
              Payouts
            </Link>
            <Link
              href="/affiliate/dashboard"
              className="inline-block rounded-lg border border-white/20 bg-white/10 px-5 py-2.5 text-sm font-semibold text-white hover:bg-white/15"
            >
              Affiliate dashboard
            </Link>
          </div>
        </div>
      </div>
    </>
  )
}
