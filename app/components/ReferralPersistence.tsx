"use client"

import { useEffect } from "react"
import { usePathname } from "next/navigation"
import { persistReferralCodeFromUrl } from "@/lib/referralPersistence"

/**
 * Persists `?ref=` from the current URL into localStorage for signup/OAuth flows.
 * Uses window.location.search inside useEffect only (no useSearchParams) to avoid
 * root-layout Suspense/hook-order issues during OAuth redirects.
 */
export default function ReferralPersistence() {
  const pathname = usePathname()

  useEffect(() => {
    persistReferralCodeFromUrl()
  }, [pathname])

  return null
}
