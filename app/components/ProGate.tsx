"use client"

import React from "react"
import Link from "next/link"

import { TRADETRAXS_PRO_PLAN } from "@/lib/tradeTraxsPlans"

type ProGateProps = {
  isPro?: boolean
  children: React.ReactNode
}

export default function ProGate({ isPro, children }: ProGateProps) {
  if (isPro) {
    return <>{children}</>
  }

  return (
    <div className="bg-white/5 border border-white/10 rounded-xl p-6 text-center text-gray-100">
      <h2 className="text-xl font-semibold mb-2">🔒 Pro Feature</h2>
      <p className="text-sm text-gray-300 mb-4">
        Upgrade to {TRADETRAXS_PRO_PLAN.name} in Settings → Subscription.
      </p>
      <Link
        href="/settings"
        className="inline-block bg-blue-500 hover:bg-blue-600 px-4 py-2 rounded font-semibold text-white disabled:hover:bg-blue-500"
      >
        Open settings
      </Link>
    </div>
  )
}

