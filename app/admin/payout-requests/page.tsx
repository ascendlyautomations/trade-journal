"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import Navbar from "@/app/components/Navbar"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"

/** Placeholder for upcoming admin payout review UI; data lives in `affiliate_payout_requests`. */
export default function AdminPayoutRequestsPlaceholderPage() {
  const router = useRouter()
  const [checking, setChecking] = useState(true)

  useEffect(() => {
    let cancelled = false
    void (async () => {
      const check = await getCurrentAdminCheckResult()
      if (!check.userId) {
        router.replace("/login")
        return
      }
      if (!check.isAdmin) {
        router.replace("/dashboard")
        return
      }
      if (!cancelled) setChecking(false)
    })()
    return () => {
      cancelled = true
    }
  }, [router])

  if (checking) {
    return (
      <>
        <Navbar />
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-8 text-white">
          Checking admin access…
        </div>
      </>
    )
  }

  return (
    <>
      <Navbar />
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-gray-100 p-4 md:p-8">
        <div className="mx-auto max-w-2xl space-y-6">
          <Link href="/admin" className="text-sm text-blue-300 hover:text-blue-200">
            ← Admin home
          </Link>
          <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent md:text-3xl">
            Affiliate payout requests
          </h1>
          <div className="rounded-xl border border-white/10 bg-white/5 p-6">
            <p className="text-sm text-gray-300">
              Admin review for <code className="text-gray-200">affiliate_payout_requests</code> is not built
              yet. Affiliates can submit requests from the Payouts page; this screen will list and process them
              in a later phase.
            </p>
            <p className="mt-3 text-sm text-gray-500">
              Table: <span className="font-mono text-gray-400">public.affiliate_payout_requests</span> (statuses:{" "}
              pending, approved, paid, rejected).
            </p>
          </div>
        </div>
      </div>
    </>
  )
}
