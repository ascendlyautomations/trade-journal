"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoPropfirmRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/analytics/propfirm")
  }, [router])

  return null
}
