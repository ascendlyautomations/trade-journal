"use client"

import { useRouter } from "next/navigation"
import { useEffect, useState } from "react"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"

export default function AffiliatePayoutSetupReturnPage() {
  const router = useRouter()
  const [message, setMessage] = useState("Updating your payout status…")

  useEffect(() => {
    let cancelled = false
    void (async () => {
      try {
        const res = await fetch("/api/affiliates/connect/sync", {
          method: "POST",
          credentials: "include",
          headers: {
            ...(await supabaseBearerHeaders()),
          },
        })
        const data = (await res.json().catch(() => ({}))) as {
          ok?: boolean
          error?: string
        }
        if (!cancelled) {
          if (res.ok && data.ok !== false) {
            setMessage("Payout setup updated. Redirecting…")
            router.replace("/payouts?setup=return")
            return
          }
          setMessage(
            toUserFacingErrorMessage(
              data.error,
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
  }, [router])

  return (
    <>
      <div className="flex min-h-[50vh] flex-col items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] px-4 text-center text-white">
        <p className="text-sm text-gray-300">{message}</p>
      </div>
    </>
  )
}
