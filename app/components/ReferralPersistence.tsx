"use client"

import { useEffect } from "react"
import { usePathname, useSearchParams } from "next/navigation"
import { persistReferralCodeFromUrl } from "@/lib/referralPersistence"

/** Persists `?ref=` from any route into localStorage for signup/OAuth flows. */
export default function ReferralPersistence() {
  const searchParams = useSearchParams()
  const pathname = usePathname()

  useEffect(() => {
    const ref = searchParams.get("ref")?.trim()
    if (!ref) return
    persistReferralCodeFromUrl(`?${searchParams.toString()}`)
  }, [searchParams, pathname])

  return null
}
