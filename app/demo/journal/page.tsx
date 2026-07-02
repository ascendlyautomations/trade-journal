"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoJournalRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/app")
  }, [router])

  return null
}
