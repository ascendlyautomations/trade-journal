"use client"

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { enableDemoMode } from "@/lib/demo/demoMode"

export default function DemoAnalystRedirectPage() {
  const router = useRouter()

  useEffect(() => {
    enableDemoMode()
    router.replace("/analyst")
  }, [router])

  return null
}
