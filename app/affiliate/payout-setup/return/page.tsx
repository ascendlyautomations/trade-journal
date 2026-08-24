"use client"

import { useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import { syncAffiliateConnectStatus } from "@/lib/affiliateConnectSyncClient"
import { useUserProfile } from "@/lib/useUserProfile"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export default function AffiliatePayoutSetupReturnPage() {
  const router = useRouter()
  const { user } = useUserProfile()
  const [message, setMessage] = useState("Updating your payout status…")

  useEffect(() => {
    if (!user?.id) return
    let cancelled = false
    void (async () => {
      try {
        const sync = await syncAffiliateConnectStatus(user.id, { force: true })
        if (!cancelled) {
          if (sync.ok) {
            setMessage("Payout setup updated. Redirecting…")
            router.replace("/payouts?setup=return")
            return
          }
          setMessage(
            toUserFacingErrorMessage(
              sync.error,
              "Could not refresh status. Please try again."
            )
          )
        }
      } catch {
        if (!cancelled) {
          setMessage("Could not refresh status. Please try again.")
        }
      }
      if (!cancelled) {
        window.setTimeout(() => router.replace("/payouts?setup=return"), 2200)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [router, user?.id])

  return (
    <>
      <div className="flex min-h-[50vh] flex-col items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 text-center text-white">
        <p className="text-sm text-gray-300">{message}</p>
      </div>
    </>
  )
}
